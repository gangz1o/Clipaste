import SwiftUI
import Observation

extension AISettingsViewModel {
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
            urlString += "\(model):generateContent"
        }

        guard let url = AIEndpointPolicy.validatedURL(from: urlString) else {
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
                request.addValue(token, forHTTPHeaderField: "x-goog-api-key")
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
