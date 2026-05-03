import Foundation

enum DefaultAISkillPreset: String, CaseIterable {
    case extractEmails
    case summarizeText
    case translateToEnglish
    case improveWriting
    case formatJSON
    case minifyJSON
    case jsonToTypeScript
    case explainCode

    var localizedName: String {
        localized(nameKey)
    }

    var localizedPrompt: String {
        localized(promptKey)
    }

    var supportedContentTypes: Set<ClipboardContentType> {
        switch self {
        case .extractEmails:
            return [.text, .link, .code, .image]
        case .formatJSON, .minifyJSON, .jsonToTypeScript, .explainCode:
            return [.text, .code]
        case .summarizeText, .translateToEnglish, .improveWriting:
            return [.text, .link, .code, .image]
        }
    }

    var outputMode: AISkillOutputMode {
        switch self {
        case .summarizeText, .explainCode:
            return .openConversation
        case .extractEmails, .translateToEnglish, .improveWriting, .formatJSON, .minifyJSON, .jsonToTypeScript:
            return .copyToClipboard
        }
    }

    var opensConversation: Bool {
        switch self {
        case .summarizeText, .explainCode:
            return true
        case .extractEmails, .translateToEnglish, .improveWriting, .formatJSON, .minifyJSON, .jsonToTypeScript:
            return false
        }
    }

    private var nameKey: String.LocalizationValue {
        switch self {
        case .extractEmails: return "Preset Skill Extract Emails"
        case .summarizeText: return "Preset Skill Summarize Text"
        case .translateToEnglish: return "Preset Skill Translate to English"
        case .improveWriting: return "Preset Skill Improve Writing"
        case .formatJSON: return "Preset Skill Format JSON"
        case .minifyJSON: return "Preset Skill Minify JSON"
        case .jsonToTypeScript: return "Preset Skill JSON to TypeScript"
        case .explainCode: return "Preset Skill Explain Code"
        }
    }

    private var promptKey: String.LocalizationValue {
        switch self {
        case .extractEmails: return "Preset Prompt Extract Emails"
        case .summarizeText: return "Preset Prompt Summarize Text"
        case .translateToEnglish: return "Preset Prompt Translate to English"
        case .improveWriting: return "Preset Prompt Improve Writing"
        case .formatJSON: return "Preset Prompt Format JSON"
        case .minifyJSON: return "Preset Prompt Minify JSON"
        case .jsonToTypeScript: return "Preset Prompt JSON to TypeScript"
        case .explainCode: return "Preset Prompt Explain Code"
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
        return String(localized: key, locale: language.resolvedLocale)
    }
}
