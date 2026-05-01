import SwiftUI
import Observation

enum AITestResult: Equatable {
    case success(String)
    case failure(String)
}

@Observable
final class AISettingsViewModel {

    // MARK: - Persistent State

    /// All saved AI configurations.
    var configurations: [AIConfiguration] = []

    /// The ID of the configuration currently selected as "active" (used by the clipboard panel).
    var activeConfigurationID: UUID? = nil

    // MARK: - Sheet / Editor State

    var isEditorPresented: Bool = false
    var editingConfiguration: AIConfiguration = AIConfiguration()
    var isEditingExisting: Bool = false

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
        save()
    }

    func setActive(_ config: AIConfiguration) {
        activeConfigurationID = config.id
        save()
    }

    var activeConfiguration: AIConfiguration? {
        configurations.first { $0.id == activeConfigurationID }
    }

    // MARK: - Persistence

    private let configurationsKey = "ai_configurations"
    private let activeIDKey = "ai_active_configuration_id"

    private func save() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configurationsKey)
        }
        UserDefaults.standard.set(activeConfigurationID?.uuidString, forKey: activeIDKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: configurationsKey),
           let decoded = try? JSONDecoder().decode([AIConfiguration].self, from: data) {
            configurations = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idString) {
            activeConfigurationID = uuid
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
