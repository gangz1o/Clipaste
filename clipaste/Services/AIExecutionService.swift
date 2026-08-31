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

        let boundedImageData: Data? = await Task.detached(priority: .utility, operation: { () -> Data? in
            let metadata = ImageProcessor.metadata(for: imageData)
            guard ClipboardImageResourcePolicy.allowsStoredImage(metadata) else { return nil }
            return ImageProcessor.generateThumbnail(
                from: imageData,
                maxPixelSize: ClipboardImageResourcePolicy.maximumOCRPixelSize
            )
        }).value
        guard let boundedImageData, Task.isCancelled == false else {
            throw AIExecutionError.unsupportedContent
        }

        let prompt = "Extract all text from this image verbatim. Output only the raw text exactly as it appears, preserving line breaks. Do not add any commentary, explanations, or formatting."
        let mediaType = "image/png"
        let base64 = boundedImageData.base64EncodedString()

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

}
