import Darwin
import Foundation
import os

struct LinkMetadataResolvedAddress: Sendable, Equatable {
    enum Family: Sendable {
        case ipv4
        case ipv6
    }

    let family: Family
    let bytes: [UInt8]
}

protocol LinkMetadataHostResolving: Sendable {
    /// This is a blocking operation. Callers must invoke it off MainActor.
    nonisolated func addresses(for host: String) -> [LinkMetadataResolvedAddress]
}

struct SystemLinkMetadataHostResolver: LinkMetadataHostResolving {
    nonisolated init() {}

    nonisolated func addresses(for host: String) -> [LinkMetadataResolvedAddress] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0 else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: [LinkMetadataResolvedAddress] = []
        var cursor = result
        while let entry = cursor?.pointee {
            if entry.ai_family == AF_INET,
               let socketAddress = entry.ai_addr?.withMemoryRebound(
                   to: sockaddr_in.self,
                   capacity: 1,
                   { $0.pointee }
               ) {
                var address = socketAddress.sin_addr
                let bytes = withUnsafeBytes(of: &address) { Array($0) }
                addresses.append(LinkMetadataResolvedAddress(family: .ipv4, bytes: bytes))
            } else if entry.ai_family == AF_INET6,
                      let socketAddress = entry.ai_addr?.withMemoryRebound(
                          to: sockaddr_in6.self,
                          capacity: 1,
                          { $0.pointee }
                      ) {
                var address = socketAddress.sin6_addr
                let bytes = withUnsafeBytes(of: &address) { Array($0) }
                addresses.append(LinkMetadataResolvedAddress(family: .ipv6, bytes: bytes))
            }
            cursor = entry.ai_next
        }
        return addresses
    }
}

enum LinkMetadataNetworkPolicy {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clipaste",
        category: "LinkMetadataSecurity"
    )

    nonisolated static func isAllowedURL(
        _ url: URL,
        resolver: any LinkMetadataHostResolving
    ) async -> Bool {
        guard syntacticallyAllowedURL(url), let host = url.host else {
            logger.warning("Blocked a link metadata request with an invalid network URL")
            return false
        }
        let isAllowed = await Task.detached(priority: .utility) {
            isPublicHost(host, resolver: resolver)
        }.value
        if isAllowed == false {
            logger.warning("Blocked a link metadata request whose destination was not exclusively public")
        }
        return isAllowed
    }

    nonisolated static func isAllowedURLFromBackground(
        _ url: URL,
        resolver: any LinkMetadataHostResolving
    ) -> Bool {
        guard syntacticallyAllowedURL(url), let host = url.host else {
            logger.warning("Blocked a redirected link metadata request with an invalid network URL")
            return false
        }
        let isAllowed = isPublicHost(host, resolver: resolver)
        if isAllowed == false {
            logger.warning("Blocked a redirected link metadata request whose destination was not exclusively public")
        }
        return isAllowed
    }

    nonisolated static func syntacticallyAllowedURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host,
              host.isEmpty == false,
              host.contains("%") == false else {
            return false
        }
        return true
    }

    nonisolated static func isPublicHost(
        _ host: String,
        resolver: any LinkMetadataHostResolving
    ) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let addresses = resolver.addresses(for: normalizedHost)
        return addresses.isEmpty == false && addresses.allSatisfy(isPublicAddress)
    }

    nonisolated static func isPublicAddress(_ address: LinkMetadataResolvedAddress) -> Bool {
        switch address.family {
        case .ipv4:
            return isPublicIPv4(address.bytes)
        case .ipv6:
            return isPublicIPv6(address.bytes)
        }
    }

    nonisolated private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]

        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100 && 64...127 ~= second { return false }
        if first == 169 && second == 254 { return false }
        if first == 172 && 16...31 ~= second { return false }
        if first == 192 && second == 168 { return false }
        if first == 192 && second == 0 { return false }
        if first == 192 && second == 88 && bytes[2] == 99 { return false }
        if first == 198 && (second == 18 || second == 19) { return false }
        if first == 198 && second == 51 && bytes[2] == 100 { return false }
        if first == 203 && second == 0 && bytes[2] == 113 { return false }
        return true
    }

    nonisolated private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }

        // IPv4-mapped IPv6 must be classified by its embedded IPv4 address.
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return false
        }

        // Only globally routable unicast (2000::/3) is accepted. This rejects
        // unspecified, loopback, ULA, link-local, multicast, documentation,
        // translation and other special-purpose ranges conservatively.
        guard bytes[0] & 0xe0 == 0x20 else { return false }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] & 0xfe == 0 {
            return false
        }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 {
            return false
        }
        if bytes[0] == 0x20, bytes[1] == 0x02 { return false }
        if bytes[0] == 0x3f, bytes[1] == 0xff, bytes[2] & 0xf0 == 0 { return false }
        return true
    }
}
