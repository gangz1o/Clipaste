import SwiftUI
import Observation

enum AITestResult: Equatable {
    case success(String)
    case failure(String)
}

@Observable
final class AISettingsViewModel {
    static let shared = AISettingsViewModel()

    // MARK: - Persistent State

    /// All saved AI configurations.
    var configurations: [AIConfiguration] = []

    /// The ID of the configuration currently selected as "active" (used by the clipboard panel).
    var activeConfigurationID: UUID? = nil

    /// User-defined AI actions shown in the clipboard item context menu.
    var skills: [AISkill] = []

    /// Last AI skill executed from the clipboard panel, used to make repeated actions faster.
    var lastUsedSkillID: UUID? = nil

    /// Master switch for surfacing AI features in the clipboard panel.
    var isAIEnabled: Bool = true {
        didSet {
            guard oldValue != isAIEnabled else { return }
            defaults.set(isAIEnabled, forKey: aiEnabledKey)
        }
    }

    /// When `true`, the image OCR right-click action prefers the active AI configuration
    /// (multimodal request) and falls back to Vision OCR on failure.
    /// Auto-disabled when no configuration is available.
    var isAIOCREnabled: Bool = false {
        didSet {
            guard oldValue != isAIOCREnabled else { return }
            defaults.set(isAIOCREnabled, forKey: aiOCREnabledKey)
        }
    }

    var canEnableAIOCR: Bool {
        configurations.isEmpty == false
    }

    // MARK: - Sheet / Editor State

    var isEditorPresented: Bool = false
    var editingConfiguration: AIConfiguration = AIConfiguration()
    var isEditingExisting: Bool = false

    var isSkillEditorPresented: Bool = false
    var editingSkill: AISkill = AISkill()
    var isEditingExistingSkill: Bool = false
    /// Inline validation error shown in the skill editor (e.g. duplicate name).
    /// Stored as a localized string so the view can render it directly.
    var skillEditorError: String? = nil

    // MARK: - Connection Test State

    var isTesting: Bool = false
    var testResult: AITestResult? = nil

    let defaults: UserDefaults
    let credentialStore: any AICredentialStoring
    var canPersistSanitizedConfigurations = true

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any AICredentialStoring = AIKeychainCredentialStore.shared
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        load()
    }

    // MARK: - CRUD

    func addNew() {
        editingConfiguration = AIConfiguration()
        isEditingExisting = false
        testResult = nil
        isEditorPresented = true
    }

    func edit(_ config: AIConfiguration) {
        editingConfiguration = config
        isEditingExisting = true
        testResult = nil
        isEditorPresented = true
    }

    func saveEditing() {
        let endpoint = editingConfiguration.endpoint.isEmpty
            ? editingConfiguration.providerType.defaultEndpoint
            : editingConfiguration.endpoint
        guard AIEndpointPolicy.validatedURL(from: endpoint) != nil else {
            testResult = .failure("Invalid Endpoint URL")
            return
        }

        guard let preparedConfigurations = configurationsReadyForSanitizedPersistence(
            configurations
        ) else {
            testResult = .failure("Existing API keys could not be migrated to Keychain. No configuration changes were saved.")
            return
        }

        do {
            try credentialStore.setCredential(
                editingConfiguration.apiKey,
                for: editingConfiguration.id
            )
        } catch {
            testResult = .failure(error.localizedDescription)
            return
        }

        configurations = preparedConfigurations
        canPersistSanitizedConfigurations = true

        if isEditingExisting {
            if let index = configurations.firstIndex(where: { $0.id == editingConfiguration.id }) {
                configurations[index] = editingConfiguration
            }
        } else {
            configurations.append(editingConfiguration)
            // Auto-activate the first config added
            if configurations.count == 1 {
                activeConfigurationID = editingConfiguration.id
            }
        }
        isEditorPresented = false
        save(includeConfigurations: true)
    }

    func delete(_ config: AIConfiguration) {
        guard let remainingConfigurations = configurationsReadyForSanitizedPersistence(
            configurations.filter { $0.id != config.id }
        ) else {
            testResult = .failure("Existing API keys could not be migrated to Keychain. The configuration was not deleted.")
            return
        }

        do {
            try credentialStore.deleteCredential(for: config.id)
        } catch {
            testResult = .failure(error.localizedDescription)
            return
        }

        configurations = remainingConfigurations
        canPersistSanitizedConfigurations = true
        if activeConfigurationID == config.id {
            activeConfigurationID = configurations.first?.id
        }
        if configurations.isEmpty {
            isAIOCREnabled = false
        }
        save(includeConfigurations: true)
    }

    func setActive(_ config: AIConfiguration) {
        activeConfigurationID = config.id
        save()
    }

    var activeConfiguration: AIConfiguration? {
        guard isAIEnabled else { return nil }
        return configurations.first { $0.id == activeConfigurationID }
    }

    func addNewSkill() {
        editingSkill = AISkill(sortOrder: skills.count)
        isEditingExistingSkill = false
        skillEditorError = nil
        isSkillEditorPresented = true
    }

    func edit(_ skill: AISkill) {
        editingSkill = skill
        isEditingExistingSkill = true
        skillEditorError = nil
        isSkillEditorPresented = true
    }

    /// Returns true when another skill (excluding the one currently being edited)
    /// already has the same trimmed, case-insensitive name.
    func isDuplicateSkillName(_ name: String, excluding id: UUID) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return false }
        return skills.contains { skill in
            skill.id != id &&
                skill.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    func saveEditingSkill() {
        editingSkill.name = editingSkill.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if isDuplicateSkillName(editingSkill.name, excluding: editingSkill.id) {
            skillEditorError = String(localized: "Skill Name Already Exists")
            return
        }

        skillEditorError = nil

        if isEditingExistingSkill {
            if let index = skills.firstIndex(where: { $0.id == editingSkill.id }) {
                skills[index] = editingSkill
            }
        } else {
            skills.append(editingSkill)
        }

        normalizeSkillSortOrder()
        isSkillEditorPresented = false
        save()
    }

    func delete(_ skill: AISkill) {
        skills.removeAll { $0.id == skill.id }
        normalizeSkillSortOrder()
        save()
    }

    func moveSkills(from source: IndexSet, to destination: Int) {
        skills.move(fromOffsets: source, toOffset: destination)
        normalizeSkillSortOrder()
        save()
    }

    func setSkillEnabled(_ skill: AISkill, isEnabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index].isEnabled = isEnabled
        save()
    }

    func addDefaultSkillsIfMissing() {
        let existingPresetIDs = Set(skills.compactMap(\.presetIdentifier))
        let missingPresets = Self.defaultSkills(startingSortOrder: skills.count)
            .filter { skill in
                guard let presetIdentifier = skill.presetIdentifier else { return false }
                return existingPresetIDs.contains(presetIdentifier) == false
            }

        guard missingPresets.isEmpty == false else { return }

        skills.append(contentsOf: missingPresets)
        normalizeSkillSortOrder()
        save()
    }

    func availableSkills(for item: ClipboardItem) -> [AISkill] {
        guard isAIEnabled else { return [] }
        return skills
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { $0.supports(item) && $0.displayTitle.isEmpty == false }
    }

    func lastUsedAvailableSkill(for item: ClipboardItem) -> AISkill? {
        guard let lastUsedSkillID else { return nil }
        return availableSkills(for: item).first { $0.id == lastUsedSkillID }
    }

    func markSkillUsed(_ skill: AISkill) {
        lastUsedSkillID = skill.id
        defaults.set(skill.id.uuidString, forKey: lastUsedSkillIDKey)
    }

    // MARK: - Persistence

    let configurationsKey = "ai_configurations"
    let activeIDKey = "ai_active_configuration_id"
    let skillsKey = "ai_skills"
    let aiEnabledKey = "ai_enabled"
    let aiOCREnabledKey = "ai_ocr_enabled"
    let lastUsedSkillIDKey = "ai_last_used_skill_id"
}
