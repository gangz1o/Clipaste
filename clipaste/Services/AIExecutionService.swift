import Foundation

enum AIExecutionError: LocalizedError {
    case missingAPIKey
    case unsupportedContent
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case requestTimedOut
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "API Key is missing")
        case .unsupportedContent:
            return String(localized: "This AI skill does not support the selected clipboard item.")
        case .invalidEndpoint:
            return String(localized: "Invalid Endpoint URL")
        case .invalidResponse:
            return String(localized: "Invalid response from server")
        case .requestFailed(let statusCode, let message):
            let format = String(localized: "AI request failed (%lld): %@")
            return String(format: format, Int64(statusCode), message)
        case .requestTimedOut:
            return String(localized: "AI request timed out. Please try again.")
        case .emptyResponse:
            return String(localized: "AI returned an empty response.")
        }
    }
}

struct AIChatMessage: Equatable, Hashable, Sendable {
    var role: String
    var content: String
}

final class AIExecutionService {
    static let shared = AIExecutionService()

    private init() {}

    func run(skill: AISkill, item: ClipboardItem, configuration: AIConfiguration) async throws -> String {
        guard skill.supports(item) else {
            throw AIExecutionError.unsupportedContent
        }

        let prompt = try await prompt(for: skill, item: item)
        return try await send(messages: [AIChatMessage(role: "user", content: prompt)], configuration: configuration)
    }

    func prompt(for skill: AISkill, item: ClipboardItem) async throws -> String {
        let text = try await sourceText(for: item)
        return renderPrompt(skill.promptTemplate, item: item, text: text)
    }

    /// Runs an OCR pass using a multimodal AI configuration. Throws on any failure so the caller
    /// can decide whether to fall back (e.g., to Vision OCR).
    func runVisionOCR(imageData: Data, configuration: AIConfiguration) async throws -> String {
        guard configuration.apiKey.isEmpty == false else {
            throw AIExecutionError.missingAPIKey
        }

        let prompt = "Extract all text from this image verbatim. Output only the raw text exactly as it appears, preserving line breaks. Do not add any commentary, explanations, or formatting."
        let mediaType = ImageProcessor.mimeType(for: imageData) ?? "image/png"
        let base64 = imageData.base64EncodedString()

        return try await withTimeout(seconds: 60) {
            switch configuration.providerType {
            case .claude:
                return try await self.sendClaudeVision(prompt: prompt, mediaType: mediaType, base64: base64, configuration: configuration)
            case .gemini:
                return try await self.sendGeminiVision(prompt: prompt, mediaType: mediaType, base64: base64, configuration: configuration)
            case .openai, .deepseek, .custom:
                return try await self.sendOpenAIVision(prompt: prompt, mediaType: mediaType, base64: base64, configuration: configuration)
            }
        }
    }

    func send(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        guard configuration.apiKey.isEmpty == false else {
            throw AIExecutionError.missingAPIKey
        }

        return try await withTimeout(seconds: 30) {
            switch configuration.providerType {
            case .claude:
                return try await self.sendClaude(messages: messages, configuration: configuration)
            case .gemini:
                return try await self.sendGemini(messages: messages, configuration: configuration)
            case .openai, .deepseek, .custom:
                return try await self.sendOpenAICompatible(messages: messages, configuration: configuration)
            }
        }
    }

    private func sourceText(for item: ClipboardItem) async throws -> String {
        switch item.contentType {
        case .text, .link, .code, .color, .fileURL:
            let loadedText = await StorageManager.shared.loadPlainText(id: item.id)
            return loadedText ?? item.rawText ?? item.textPreview
        case .image:
            var imageData = await StorageManager.shared.loadImageData(id: item.id)
            if imageData == nil {
                imageData = await StorageManager.shared.loadPreviewImageData(id: item.id)
            }
            if let imageData,
               let recognizedText = await OCREngine.extractText(from: imageData),
               recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return recognizedText
            }
            throw AIExecutionError.unsupportedContent
        }
    }

    private func renderPrompt(_ template: String, item: ClipboardItem, text: String) -> String {
        template
            .replacingOccurrences(of: "{{clipboard.text}}", with: text)
            .replacingOccurrences(of: "{{clipboard.title}}", with: item.customTitle ?? item.linkTitle ?? item.textPreview)
            .replacingOccurrences(of: "{{clipboard.type}}", with: item.contentType.rawValue)
    }

    private func sendOpenAICompatible(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = URL(string: endpoint) else {
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

    private func sendClaude(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = URL(string: endpoint) else {
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

    private func sendGemini(messages: [AIChatMessage], configuration: AIConfiguration) async throws -> String {
        var endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        if endpoint.hasSuffix("/") == false { endpoint += "/" }
        endpoint += "\(configuration.model):generateContent?key=\(configuration.apiKey)"

        guard let url = URL(string: endpoint) else {
            throw AIExecutionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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

    private func sendOpenAIVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = URL(string: endpoint) else { throw AIExecutionError.invalidEndpoint }

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

    private func sendClaudeVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        let endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        guard let url = URL(string: endpoint) else { throw AIExecutionError.invalidEndpoint }

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

    private func sendGeminiVision(prompt: String, mediaType: String, base64: String, configuration: AIConfiguration) async throws -> String {
        var endpoint = configuration.endpoint.isEmpty ? configuration.providerType.defaultEndpoint : configuration.endpoint
        if endpoint.hasSuffix("/") == false { endpoint += "/" }
        endpoint += "\(configuration.model):generateContent?key=\(configuration.apiKey)"

        guard let url = URL(string: endpoint) else { throw AIExecutionError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExecutionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIExecutionError.requestFailed(httpResponse.statusCode, message)
        }

        return data
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AIExecutionError.requestTimedOut
            }

            guard let value = try await group.next() else {
                throw AIExecutionError.requestTimedOut
            }

            group.cancelAll()
            return value
        }
    }
}
