import Foundation

struct AICredentialHydrationResult {
    let configurations: [AIConfiguration]
    let shouldRewritePersistentConfigurations: Bool
    let canPersistSanitizedConfigurations: Bool
}

enum AICredentialMigrationPolicy {
    static func hydrate(
        configurations: [AIConfiguration],
        credentialStore: any AICredentialStoring
    ) -> AICredentialHydrationResult {
        var hydrated = configurations
        var sawLegacyCredential = false
        var migrationSucceeded = true

        for index in hydrated.indices {
            if hydrated[index].apiKey.isEmpty == false {
                sawLegacyCredential = true
                do {
                    try credentialStore.setCredential(
                        hydrated[index].apiKey,
                        for: hydrated[index].id
                    )
                } catch {
                    migrationSucceeded = false
                }
                continue
            }

            hydrated[index].apiKey = (try? credentialStore.credential(
                for: hydrated[index].id
            )) ?? ""
        }

        return AICredentialHydrationResult(
            configurations: hydrated,
            shouldRewritePersistentConfigurations: sawLegacyCredential && migrationSucceeded,
            canPersistSanitizedConfigurations: sawLegacyCredential == false || migrationSucceeded
        )
    }
}
