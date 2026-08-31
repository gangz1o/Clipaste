import Foundation

extension AIExecutionService {
    func sendOpenAICompatible(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else {
            throw AIExecutionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.2,
            "max_tokens": 4096,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIExecutionError.invalidResponse
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

    func sendClaude(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else {
            throw AIExecutionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": 4096,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIExecutionError.invalidResponse
        }

        let text = contentBlocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

    func sendGemini(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        var endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        if endpoint.hasSuffix("/") == false { endpoint += "/" }
        endpoint += "\(configuration.model):generateContent"

        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else {
            throw AIExecutionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")

        let contents = messages.map { message in
            [
                "role": message.role == "assistant" ? "model" : "user",
                "parts": [["text": message.content]]
            ] as [String: Any]
        }
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["temperature": 0.2]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIExecutionError.invalidResponse
        }

        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

    func sendOpenAIVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else { throw AIExecutionError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let dataURL = "data:\(mediaType);base64,\(base64)"
        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": content]],
            "temperature": 0.0,
            "max_tokens": 4096,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let messageContent = message["content"] as? String else {
            throw AIExecutionError.invalidResponse
        }

        let trimmed = messageContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

    func sendClaudeVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else { throw AIExecutionError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": base64]],
            ["type": "text", "text": prompt]
        ]
        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": content]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIExecutionError.invalidResponse
        }

        let text = contentBlocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

    func sendGeminiVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        var endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        if endpoint.hasSuffix("/") == false { endpoint += "/" }
        endpoint += "\(configuration.model):generateContent"

        guard let url = AIEndpointPolicy.validatedURL(from: endpoint) else { throw AIExecutionError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")

        let parts: [[String: Any]] = [
            ["text": prompt],
            ["inline_data": ["mime_type": mediaType, "data": base64]]
        ]
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["temperature": 0.0]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]] else {
            throw AIExecutionError.invalidResponse
        }

        let text = responseParts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AIExecutionError.emptyResponse }
        return trimmed
    }

}
