import Foundation

private final class CredentialStoreSpy: AICredentialStoring, @unchecked Sendable {
    enum Failure: Error { case writeRejected }

    var credentials: [UUID: String] = [:]
    var rejectsWrites = false

    func credential(for configurationID: UUID) throws -> String? {
        credentials[configurationID]
    }

    func setCredential(_ credential: String, for configurationID: UUID) throws {
        if rejectsWrites { throw Failure.writeRejected }
        credentials[configurationID] = credential
    }

    func deleteCredential(for configurationID: UUID) throws {
        credentials.removeValue(forKey: configurationID)
    }
}

@main
enum AISecretsAndEndpointTests {
    static func main() throws {
        testEndpointPolicy()
        try testConfigurationEncodingOmitsSecret()
        testLegacyCredentialMigration()
        try testCredentialStoreSourceContract()
        try testGeminiCredentialTransportContract()
        print("AISecretsAndEndpointTests passed")
    }

    private static func testLegacyCredentialMigration() {
        let configuration = AIConfiguration(
            providerType: .custom,
            apiKey: "legacy-secret",
            endpoint: "https://api.example.com/v1",
            model: "test-model"
        )

        let successStore = CredentialStoreSpy()
        let successful = AICredentialMigrationPolicy.hydrate(
            configurations: [configuration],
            credentialStore: successStore
        )
        precondition(successful.shouldRewritePersistentConfigurations)
        precondition(successful.canPersistSanitizedConfigurations)
        precondition(successStore.credentials[configuration.id] == "legacy-secret")

        let failureStore = CredentialStoreSpy()
        failureStore.rejectsWrites = true
        let failed = AICredentialMigrationPolicy.hydrate(
            configurations: [configuration],
            credentialStore: failureStore
        )
        precondition(failed.shouldRewritePersistentConfigurations == false)
        precondition(failed.canPersistSanitizedConfigurations == false)
        precondition(failed.configurations.first?.apiKey == "legacy-secret")

        let hydratedConfiguration = AIConfiguration(
            id: configuration.id,
            providerType: .custom,
            endpoint: "https://api.example.com/v1",
            model: "test-model"
        )
        let readStore = CredentialStoreSpy()
        readStore.credentials[configuration.id] = "keychain-secret"
        let hydrated = AICredentialMigrationPolicy.hydrate(
            configurations: [hydratedConfiguration],
            credentialStore: readStore
        )
        precondition(hydrated.configurations.first?.apiKey == "keychain-secret")
        precondition(hydrated.shouldRewritePersistentConfigurations == false)
        precondition(hydrated.canPersistSanitizedConfigurations)
    }

    private static func testEndpointPolicy() {
        precondition(AIEndpointPolicy.validatedURL(from: "https://api.example.com/v1") != nil)
        precondition(AIEndpointPolicy.validatedURL(from: "http://localhost:11434/v1") != nil)
        precondition(AIEndpointPolicy.validatedURL(from: "http://127.9.8.7:8080/v1") != nil)
        precondition(AIEndpointPolicy.validatedURL(from: "http://[::1]:8080/v1") != nil)
        precondition(AIEndpointPolicy.validatedURL(from: "http://api.example.com/v1") == nil)
        precondition(AIEndpointPolicy.validatedURL(from: "ftp://api.example.com/v1") == nil)
        precondition(AIEndpointPolicy.validatedURL(from: "https://user:pass@api.example.com/v1") == nil)
    }

    private static func testConfigurationEncodingOmitsSecret() throws {
        let configuration = AIConfiguration(
            providerType: .custom,
            apiKey: "must-not-be-persisted",
            endpoint: "https://api.example.com/v1",
            model: "test-model"
        )
        let encoded = try JSONEncoder().encode([configuration])
        let json = String(decoding: encoded, as: UTF8.self)
        precondition(json.contains("must-not-be-persisted") == false)
        precondition(json.contains("apiKey") == false)

        let legacyJSON = """
        [{"id":"\(configuration.id.uuidString)","name":"Legacy","providerType":"Custom (OpenAI Compatible)","apiKey":"legacy-secret","endpoint":"https://api.example.com/v1","model":"test-model","supportsImage":false}]
        """
        let decoded = try JSONDecoder().decode([AIConfiguration].self, from: Data(legacyJSON.utf8))
        precondition(decoded.first?.apiKey == "legacy-secret")
    }

    private static func testCredentialStoreSourceContract() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("clipaste/Services/AICredentialStore.swift"),
            encoding: .utf8
        )
        precondition(source.contains("SecItemCopyMatching"))
        precondition(source.contains("SecItemUpdate"))
        precondition(source.contains("SecItemAdd"))
        precondition(source.contains("SecItemDelete"))
        precondition(source.contains("kSecAttrAccessibleAfterFirstUnlock"))
    }

    private static func testGeminiCredentialTransportContract() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let executionSource = try moduleSources(
            root,
            directory: "clipaste/Services",
            prefix: "AIExecutionService"
        )
        let settingsSource = try moduleSources(
            root,
            directory: "clipaste/ViewModels",
            prefix: "AISettingsViewModel"
        )

        precondition(executionSource.contains("?key=") == false)
        precondition(settingsSource.contains("?key=") == false)
        precondition(executionSource.components(separatedBy: "x-goog-api-key").count == 3)
        precondition(settingsSource.contains("x-goog-api-key"))
        precondition(settingsSource.contains("persistConfigurationCredentials") == false)
        precondition(settingsSource.contains("save(includeConfigurations: true)"))
        precondition(settingsSource.contains("if includeConfigurations,"))
    }

    private static func moduleSources(_ root: URL, directory: String, prefix: String) throws -> String {
        let directoryURL = root.appendingPathComponent(directory, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent.hasPrefix(prefix) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }
}
