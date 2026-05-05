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

    /// When `true`, the image OCR right-click action prefers the active AI configuration
    /// (multimodal request) and falls back to Vision OCR on failure.
    /// Auto-disabled when no configuration is available.
    var isAIOCREnabled: Bool = false {
        didSet {
            guard oldValue != isAIOCREnabled else { return }
            UserDefaults.standard.set(isAIOCREnabled, forKey: aiOCREnabledKey)
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

    // MARK: - Init

    init() {
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
        save()
    }

    func delete(_ config: AIConfiguration) {
        configurations.removeAll { $0.id == config.id }
        if activeConfigurationID == config.id {
            activeConfigurationID = configurations.first?.id
        }
        if configurations.isEmpty {
            isAIOCREnabled = false
        }
        save()
    }

    func setActive(_ config: AIConfiguration) {
        activeConfigurationID = config.id
        save()
    }

    var activeConfiguration: AIConfiguration? {
        configurations.first { $0.id == activeConfigurationID }
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
        skills
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { $0.supports(item) && $0.displayTitle.isEmpty == false }
    }

    // MARK: - Persistence

    private let configurationsKey = "ai_configurations"
    private let activeIDKey = "ai_active_configuration_id"
    private let skillsKey = "ai_skills"
    private let aiOCREnabledKey = "ai_ocr_enabled"

    private func save() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configurationsKey)
        }
        if let data = try? JSONEncoder().encode(skills) {
            UserDefaults.standard.set(data, forKey: skillsKey)
        }
        UserDefaults.standard.set(activeConfigurationID?.uuidString, forKey: activeIDKey)
    }

    private func load() {
        var shouldPersistDefaultSkills = false

        if let data = UserDefaults.standard.data(forKey: configurationsKey),
           let decoded = try? JSONDecoder().decode([AIConfiguration].self, from: data) {
            configurations = decoded
        }
        if let data = UserDefaults.standard.data(forKey: skillsKey),
           let decoded = try? JSONDecoder().decode([AISkill].self, from: data) {
            skills = decoded.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            skills = Self.defaultSkills()
            shouldPersistDefaultSkills = true
        }
        if let idString = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idString) {
            activeConfigurationID = uuid
        }

        if UserDefaults.standard.object(forKey: aiOCREnabledKey) != nil {
            isAIOCREnabled = UserDefaults.standard.bool(forKey: aiOCREnabledKey)
        }
        if configurations.isEmpty {
            isAIOCREnabled = false
        }

        if shouldPersistDefaultSkills {
            save()
        }
    }

    private func normalizeSkillSortOrder() {
        for index in skills.indices {
            skills[index].sortOrder = index
        }
    }

    private static func defaultSkills(startingSortOrder: Int = 0) -> [AISkill] {
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

    // MARK: - Connection Test

    @MainActor
    func testConnection() async {
        let config = editingConfiguration
        isTesting = true
        testResult = nil

        let token = config.apiKey
        if token.isEmpty {
            testResult = .failure("API Key is missing")
            isTesting = false
            return
        }

        var urlString = config.endpoint.isEmpty ? config.providerType.defaultEndpoint : config.endpoint
        let model = config.model.isEmpty ? (config.providerType.defaultModels.first ?? "") : config.model

        if config.providerType == .gemini {
            if !urlString.hasSuffix("/") { urlString += "/" }
            urlString += "\(model):generateContent?key=\(token)"
        }

        guard let url = URL(string: urlString) else {
            testResult = .failure("Invalid Endpoint URL")
            isTesting = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            if config.providerType == .claude {
                request.addValue(token, forHTTPHeaderField: "x-api-key")
                request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                let body: [String: Any] = [
                    "model": model, "max_tokens": 10,
                    "messages": [["role": "user", "content": "Hi"]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } else if config.providerType == .gemini {
                let body: [String: Any] = [
                    "contents": [["parts": [["text": "Hi"]]]],
                    "generationConfig": ["maxOutputTokens": 10]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } else {
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let body: [String: Any] = [
                    "model": model, "max_tokens": 10,
                    "messages": [["role": "user", "content": "Hi"]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                testResult = .failure("Invalid response from server")
                isTesting = false
                return
            }
            if (200...299).contains(httpResponse.statusCode) {
                testResult = .success("Connection successful!")
            } else {
                let errStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
                testResult = .failure("Failed (\(httpResponse.statusCode)): \(errStr)")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }
}
