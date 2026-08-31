import AppKit
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case de = "de"
    case fr = "fr"

    var id: String { self.rawValue }

    /// 语言选择器中展示的原生文案（非本地化键）。
    var nativeDisplayName: String {
        switch self {
        case .auto:   return ""
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        }
    }

    var localizedDisplayName: LocalizedStringResource {
        switch self {
        case .auto: return LocalizedStringResource("Follow System")
        case .zhHans: return LocalizedStringResource("Simplified Chinese")
        case .zhHant: return LocalizedStringResource("Traditional Chinese")
        case .en: return LocalizedStringResource("English")
        case .ja: return LocalizedStringResource("Japanese")
        case .ko: return LocalizedStringResource("Korean")
        case .de: return LocalizedStringResource("German")
        case .fr: return LocalizedStringResource("French")
        }
    }

    var locale: Locale? {
        switch self {
        case .auto:   return nil
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en:     return Locale(identifier: "en")
        case .ja:     return Locale(identifier: "ja")
        case .ko:     return Locale(identifier: "ko")
        case .de:     return Locale(identifier: "de")
        case .fr:     return Locale(identifier: "fr")
        }
    }

    var resolvedLocale: Locale {
        locale ?? Self.systemLocale
    }

    static var systemLocale: Locale {
        let globalDefaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let preferredLanguages = globalDefaults?["AppleLanguages"] as? [String],
           let languageIdentifier = preferredLanguages.first,
           languageIdentifier.isEmpty == false {
            return Locale(identifier: languageIdentifier)
        }
        return .current
    }
}
