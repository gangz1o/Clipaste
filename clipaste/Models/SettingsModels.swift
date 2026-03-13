import Foundation

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

    var displayName: String {
        switch self {
        case .auto:   return String(localized: "Follow System")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
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
}

enum VerticalFollowMode: String, CaseIterable, Identifiable {
    case statusBar = "statusBar"
    case mouse = "mouse"
    case lastPosition = "lastPosition"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .statusBar: return String(localized: "Near Status Bar Icon")
        case .mouse: return String(localized: "Near Mouse Cursor")
        case .lastPosition: return String(localized: "Last Position")
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
        case .threeDays: return String(localized: "3 Days")
        case .oneWeek: return String(localized: "1 Week")
        case .oneMonth: return String(localized: "1 Month")
        case .sixMonths: return String(localized: "6 Months")
        case .oneYear: return String(localized: "1 Year")
        case .unlimited: return String(localized: "Forever")
        }
    }
}

extension HistoryRetention {
    /// Returns a threshold date; records created before this date should be deleted.
    /// Returns nil for `.unlimited` (keep forever).
    nonisolated var expirationDate: Date? {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        switch self {
        case .threeDays:  return now.addingTimeInterval(-3 * 24 * 3600)
        case .oneWeek:    return now.addingTimeInterval(-7 * 24 * 3600)
        case .oneMonth:   return cal.date(byAdding: .month, value: -1, to: now)
        case .sixMonths:  return cal.date(byAdding: .month, value: -6, to: now)
        case .oneYear:    return cal.date(byAdding: .year,  value: -1, to: now)
        case .unlimited:  return nil
        }
    }
}

enum PasteTextFormat: String, CaseIterable, Identifiable {
    case original  = "original"
    case plainText = "plainText"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .original:  return String(localized: "Keep Original Formatting")
        case .plainText: return String(localized: "Always Plain Text")
        }
    }
}
