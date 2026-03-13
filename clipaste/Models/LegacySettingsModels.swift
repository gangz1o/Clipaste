import Foundation

/// Legacy settings models still referenced by the current tab-based settings UI.
enum PasteBehavior: String, CaseIterable, Identifiable {
    case direct = "Direct Paste to Current App"
    case clipboardOnly = "Copy to Clipboard Only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct:
            return String(localized: "Paste Directly to Active App")
        case .clipboardOnly:
            return String(localized: "Copy to Clipboard Only")
        }
    }
}

enum AppLayoutMode: String, CaseIterable, Identifiable {
    case horizontal = "Horizontal Cards"
    case vertical = "Vertical List"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontal:
            return String(localized: "Horizontal Cards")
        case .vertical:
            return String(localized: "Vertical List")
        }
    }
}

enum HistoryLimit: String, CaseIterable, Identifiable {
    case day = "1 Day"
    case week = "1 Week"
    case month = "1 Month"
    case year = "1 Year"
    case unlimited = "Unlimited"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day:
            return String(localized: "1 Day")
        case .week:
            return String(localized: "1 Week")
        case .month:
            return String(localized: "1 Month")
        case .year:
            return String(localized: "1 Year")
        case .unlimited:
            return String(localized: "Unlimited")
        }
    }
}
