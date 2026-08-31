import Foundation
import Security

protocol AICredentialStoring: Sendable {
    func credential(for configurationID: UUID) throws -> String?
    func setCredential(_ credential: String, for configurationID: UUID) throws
    func deleteCredential(for configurationID: UUID) throws
}

enum AICredentialStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "Keychain error \(status)"
        }
    }
}

struct AIKeychainCredentialStore: AICredentialStoring {
    static let shared = AIKeychainCredentialStore()

    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "clipaste") + ".ai-credentials") {
        self.service = service
    }

    func credential(for configurationID: UUID) throws -> String? {
        var query = baseQuery(for: configurationID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AICredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else {
            return nil
        }
        return credential
    }

    func setCredential(_ credential: String, for configurationID: UUID) throws {
        guard credential.isEmpty == false else {
            try deleteCredential(for: configurationID)
            return
        }

        let encodedCredential = Data(credential.utf8)
        let query = baseQuery(for: configurationID)
        let update = [kSecValueData as String: encodedCredential]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = encodedCredential
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AICredentialStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw AICredentialStoreError.unexpectedStatus(updateStatus)
        }
    }

    func deleteCredential(for configurationID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: configurationID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AICredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for configurationID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configurationID.uuidString
        ]
    }
}
