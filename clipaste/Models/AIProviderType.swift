import Foundation

enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case openai = "OpenAI"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    case gemini = "Gemini"
    case custom = "Custom (OpenAI Compatible)"
    
    var id: String { self.rawValue }
    
    var defaultEndpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .deepseek: return "https://api.deepseek.com/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/models/"
        case .custom: return ""
        }
    }
    
    var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-5.5", "gpt-5.4", "gpt-5.4-nano", "gpt-5.4-mini","gpt-4o"]
        case .claude: return ["claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6","claude-haiku-4-5-20251001"]
        case .deepseek: return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .gemini: return ["gemini-3-flash-preview","gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-pro-exp"]
        case .custom: return []
        }
    }
}
