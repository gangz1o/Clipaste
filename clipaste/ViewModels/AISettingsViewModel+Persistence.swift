import SwiftUI
import Observation

extension AISettingsViewModel {
    func save(includeConfigurations: Bool = false) {
        if includeConfigurations,
           canPersistSanitizedConfigurations,
           let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: configurationsKey)
        }
        if let data = try? JSONEncoder().encode(skills) {
            defaults.set(data, forKey: skillsKey)
        }
        defaults.set(activeConfigurationID?.uuidString, forKey: activeIDKey)
    }

    func load() {
        var shouldPersistDefaultSkills = false

        if let data = defaults.data(forKey: configurationsKey),
           let decoded = try? JSONDecoder().decode([AIConfiguration].self, from: data) {
            configurations = decoded
            hydrateAndMigrateConfigurationCredentials()
        }
        if let data = defaults.data(forKey: skillsKey),
           let decoded = try? JSONDecoder().decode([AISkill].self, from: data) {
            skills = decoded.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            skills = Self.defaultSkills()
            shouldPersistDefaultSkills = true
        }
        if let idString = defaults.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idString) {
            activeConfigurationID = uuid
        }
        if let idString = defaults.string(forKey: lastUsedSkillIDKey),
           let uuid = UUID(uuidString: idString) {
            lastUsedSkillID = uuid
        }

        if defaults.object(forKey: aiEnabledKey) != nil {
            isAIEnabled = defaults.bool(forKey: aiEnabledKey)
        }
        if defaults.object(forKey: aiOCREnabledKey) != nil {
            isAIOCREnabled = defaults.bool(forKey: aiOCREnabledKey)
        }
        if configurations.isEmpty {
            isAIOCREnabled = false
        }

        if shouldPersistDefaultSkills {
            save()
        }
    }

    func hydrateAndMigrateConfigurationCredentials() {
        let result = AICredentialMigrationPolicy.hydrate(
            configurations: configurations,
            credentialStore: credentialStore
        )
        configurations = result.configurations
        canPersistSanitizedConfigurations = result.canPersistSanitizedConfigurations

        guard result.shouldRewritePersistentConfigurations,
              let sanitizedData = try? JSONEncoder().encode(configurations) else {
            if result.canPersistSanitizedConfigurations == false {
                testResult = .failure("Existing API keys could not be migrated to Keychain. The legacy configuration was kept unchanged.")
            }
            return
        }
        defaults.set(sanitizedData, forKey: configurationsKey)
    }

    func configurationsReadyForSanitizedPersistence(
        _ candidateConfigurations: [AIConfiguration]
    ) -> [AIConfiguration]? {
        guard canPersistSanitizedConfigurations == false else {
            return candidateConfigurations
        }

        let result = AICredentialMigrationPolicy.hydrate(
            configurations: candidateConfigurations,
            credentialStore: credentialStore
        )
        guard result.canPersistSanitizedConfigurations else { return nil }

        return result.configurations
    }

    func normalizeSkillSortOrder() {
        for index in skills.indices {
            skills[index].sortOrder = index
        }
    }

    static func defaultSkills(startingSortOrder: Int = 0) -> [AISkill] {
        let presets: [DefaultAISkillPreset] = [
            .extractEmails,
            .summarizeText,
            .translateToEnglish,
            .improveWriting,
            .formatJSON,
            .minifyJSON,
            .jsonToTypeScript,
            .explainCode
        ]

        return presets.enumerated().map { offset, preset in
            AISkill(
                name: preset.localizedName,
                promptTemplate: preset.localizedPrompt,
                supportedContentTypes: preset.supportedContentTypes,
                outputMode: preset.outputMode,
                opensConversation: preset.opensConversation,
                sortOrder: startingSortOrder + offset,
                presetIdentifier: preset.rawValue
            )
        }
    }
}
