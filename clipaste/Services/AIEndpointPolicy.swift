import Foundation

enum AIEndpointPolicy {
    nonisolated static func validatedURL(from endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              let url = components.url else {
            return nil
        }

        if scheme == "https" {
            return url
        }

        guard scheme == "http", isExplicitLoopbackHost(host) else {
            return nil
        }
        return url
    }

    nonisolated static func isExplicitLoopbackHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if normalizedHost == "localhost" || normalizedHost == "::1" {
            return true
        }

        let octets = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ UInt8($0) != nil }),
              octets[0] == "127" else {
            return false
        }
        return true
    }
}
