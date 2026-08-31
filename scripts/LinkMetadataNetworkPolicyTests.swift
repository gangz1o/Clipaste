import Darwin
import Foundation

private struct FixedResolver: LinkMetadataHostResolving {
    let mapping: [String: [LinkMetadataResolvedAddress]]

    nonisolated func addresses(for host: String) -> [LinkMetadataResolvedAddress] {
        mapping[host] ?? []
    }
}

@main
enum LinkMetadataNetworkPolicyTests {
    static func main() async {
        testAddressClassification()
        await testDNSClassification()
        testRedirectClassification()
        print("LinkMetadataNetworkPolicyTests passed")
    }

    private static func testRedirectClassification() {
        let resolver = FixedResolver(mapping: [
            "redirect-public.example": [ipv4(93, 184, 216, 34)],
            "redirect-private.example": [ipv4(169, 254, 169, 254)]
        ])
        precondition(LinkMetadataNetworkPolicy.isAllowedURLFromBackground(
            URL(string: "https://redirect-public.example/next")!, resolver: resolver
        ))
        precondition(LinkMetadataNetworkPolicy.isAllowedURLFromBackground(
            URL(string: "https://redirect-private.example/next")!, resolver: resolver
        ) == false)
    }

    private static func testAddressClassification() {
        let publicIPv4 = ipv4(93, 184, 216, 34)
        precondition(LinkMetadataNetworkPolicy.isPublicAddress(publicIPv4))

        let rejectedIPv4: [LinkMetadataResolvedAddress] = [
            ipv4(0, 0, 0, 0), ipv4(10, 0, 0, 1), ipv4(100, 64, 0, 1),
            ipv4(127, 0, 0, 1), ipv4(169, 254, 1, 1), ipv4(172, 16, 0, 1),
            ipv4(192, 0, 2, 1), ipv4(192, 168, 1, 1), ipv4(198, 18, 0, 1),
            ipv4(198, 51, 100, 1), ipv4(203, 0, 113, 1), ipv4(224, 0, 0, 1)
        ]
        precondition(rejectedIPv4.allSatisfy { LinkMetadataNetworkPolicy.isPublicAddress($0) == false })

        precondition(LinkMetadataNetworkPolicy.isPublicAddress(ipv6("2606:2800:220:1:248:1893:25c8:1946")))
        let rejectedIPv6 = [
            ipv6("::"), ipv6("::1"), ipv6("fc00::1"), ipv6("fe80::1"),
            ipv6("ff02::1"), ipv6("2001::1"), ipv6("2001:db8::1"), ipv6("2002::1"),
            ipv6("3fff::1"), ipv6("::ffff:127.0.0.1"),
            ipv6("::ffff:93.184.216.34")
        ]
        precondition(rejectedIPv6.allSatisfy { LinkMetadataNetworkPolicy.isPublicAddress($0) == false })
    }

    private static func testDNSClassification() async {
        let resolver = FixedResolver(mapping: [
            "public.example": [ipv4(93, 184, 216, 34)],
            "private.example": [ipv4(10, 0, 0, 1)],
            "mixed.example": [ipv4(93, 184, 216, 34), ipv4(192, 168, 1, 1)]
        ])

        let publicAllowed = await LinkMetadataNetworkPolicy.isAllowedURL(
            URL(string: "https://public.example/page")!, resolver: resolver
        )
        let privateAllowed = await LinkMetadataNetworkPolicy.isAllowedURL(
            URL(string: "https://private.example/page")!, resolver: resolver
        )
        let mixedAllowed = await LinkMetadataNetworkPolicy.isAllowedURL(
            URL(string: "https://mixed.example/page")!, resolver: resolver
        )
        let fileAllowed = await LinkMetadataNetworkPolicy.isAllowedURL(
            URL(string: "file:///etc/passwd")!, resolver: resolver
        )

        precondition(publicAllowed)
        precondition(privateAllowed == false)
        precondition(mixedAllowed == false)
        precondition(fileAllowed == false)
    }

    private static func ipv4(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> LinkMetadataResolvedAddress {
        LinkMetadataResolvedAddress(family: .ipv4, bytes: [a, b, c, d])
    }

    private static func ipv6(_ string: String) -> LinkMetadataResolvedAddress {
        var address = in6_addr()
        precondition(inet_pton(AF_INET6, string, &address) == 1)
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        return LinkMetadataResolvedAddress(family: .ipv6, bytes: bytes)
    }
}
