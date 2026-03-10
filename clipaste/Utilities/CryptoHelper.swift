import Foundation
import CryptoKit

enum CryptoHelper {
    nonisolated static func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func generateHash(for string: String) -> String {
        sha256(data: Data(string.utf8))
    }
}
