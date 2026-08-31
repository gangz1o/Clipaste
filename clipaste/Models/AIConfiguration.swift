import Foundation

struct AIConfiguration: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var providerType: AIProviderType
    var apiKey: String
    var endpoint: String
    var model: String
    /// User-confirmed flag indicating the chosen model accepts image input (multimodal).
    /// Used to gate AI-powered OCR; falls back to Vision OCR when `false`.
    var supportsImage: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        providerType: AIProviderType = .openai,
        apiKey: String = "",
        endpoint: String = "",
        model: String = "",
        supportsImage: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.apiKey = apiKey
        self.endpoint = endpoint.isEmpty ? providerType.defaultEndpoint : endpoint
        let resolvedModel = model.isEmpty ? (providerType.defaultModels.first ?? "") : model
        self.model = resolvedModel
        self.supportsImage = supportsImage ?? AIConfiguration.defaultSupportsImage(provider: providerType, model: resolvedModel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, apiKey, endpoint, model, supportsImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let providerType = try container.decode(AIProviderType.self, forKey: .providerType)
        let apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        let endpoint = try container.decode(String.self, forKey: .endpoint)
        let model = try container.decode(String.self, forKey: .model)
        let supportsImage = try container.decodeIfPresent(Bool.self, forKey: .supportsImage)
            ?? AIConfiguration.defaultSupportsImage(provider: providerType, model: model)
        self.id = id
        self.name = name
        self.providerType = providerType
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.supportsImage = supportsImage
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(providerType, forKey: .providerType)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(model, forKey: .model)
        try container.encode(supportsImage, forKey: .supportsImage)
    }

    /// A short display label shown in the clipboard panel picker.
    var displayTitle: String {
        name.isEmpty ? providerType.localizedName : name
    }

    var providerIconAssetName: String? {
        switch providerType {
        case .openai:
            return "ai-openai"
        case .claude:
            return "ai-anthropic"
        case .deepseek:
            return "ai-deepseek"
        case .gemini:
            return "ai-googlegemini"
        case .custom:
            let searchableText = "\(name) \(model) \(endpoint)".lowercased()
            if searchableText.containsAny(["grok", "x-ai", "x.ai", "xai"]) {
                return "ai-grok"
            }
            if searchableText.containsAny(["ollama", "localhost:11434", "127.0.0.1:11434"]) {
                return "ai-ollama"
            }
            if searchableText.containsAny(["qwen", "qwq", "qvq", "tongyi", "dashscope", "千问", "通义"]) {
                return "ai-qwen"
            }
            if searchableText.containsAny(["kimi", "moonshot"]) {
                return "ai-moonshotai"
            }
            if searchableText.containsAny(["glm", "chatglm", "zhipu", "z.ai", "bigmodel", "智谱"]) {
                return "ai-zai"
            }
            if searchableText.containsAny(["minimax", "abab", "hailuo", "海螺"]) {
                return "ai-minimax"
            }
            if searchableText.contains("deepseek") {
                return "ai-deepseek"
            }
            if searchableText.contains("gemini") || searchableText.contains("google") {
                return "ai-googlegemini"
            }
            if searchableText.contains("claude") || searchableText.contains("anthropic") {
                return "ai-anthropic"
            }
            if searchableText.contains("openai") {
                return "ai-openai"
            }
            if searchableText.containsAny(["alibaba", "aliyun", "阿里云"]) {
                return "ai-alibabacloud"
            }
            return nil
        }
    }

    /// Heuristic guess for whether a provider+model combo accepts image input.
    /// Used as the default when the user hasn't toggled the flag explicitly.
    static func defaultSupportsImage(provider: AIProviderType, model: String) -> Bool {
        let lowered = model.lowercased()
        switch provider {
        case .openai:
            // gpt-4o family + gpt-5 family are multimodal.
            return lowered.contains("gpt-4o") || lowered.hasPrefix("gpt-5") || lowered.contains("vision")
        case .claude:
            // All current claude-opus / sonnet / haiku 4.x accept images.
            return lowered.hasPrefix("claude-")
        case .gemini:
            return lowered.hasPrefix("gemini-")
        case .deepseek:
            return false
        case .custom:
            return false
        }
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
