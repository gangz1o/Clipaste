import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, zhHans, zhHant, en, ja, ko, de, fr
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "跟随系统"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        }
    }

    var locale: Locale? {
        switch self {
        case .auto: return nil
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en: return Locale(identifier: "en")
        case .ja: return Locale(identifier: "ja")
        case .ko: return Locale(identifier: "ko")
        case .de: return Locale(identifier: "de")
        case .fr: return Locale(identifier: "fr")
        }
    }
}

enum VerticalFollowMode: String, CaseIterable, Identifiable {
    case statusBar = "statusBar"
    case mouse = "mouse"
    case lastPosition = "lastPosition"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .statusBar: return "出现在状态栏图标旁"
        case .mouse: return "出现在鼠标光标旁"
        case .lastPosition: return "出现在上次的位置"
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case sixMonths = "6m"
    case oneYear = "1y"
    case unlimited = "unlimited"
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .threeDays: return "3 天"
        case .oneWeek: return "1 周"
        case .oneMonth: return "1 个月"
        case .sixMonths: return "半年"
        case .oneYear: return "1 年"
        case .unlimited: return "永久"
        }
    }
}

enum PasteTextFormat: String, CaseIterable, Identifiable {
    case original  = "original"
    case plainText = "plainText"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .original:  return "保留原始格式"
        case .plainText: return "始终纯文本"
        }
    }
}
