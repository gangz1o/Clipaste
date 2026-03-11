import Foundation

/// Legacy settings models still referenced by the current tab-based settings UI.
enum PasteBehavior: String, CaseIterable, Identifiable {
    case direct = "Direct Paste to Current App"
    case clipboardOnly = "Copy to Clipboard Only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct:
            return "直接粘贴到当前应用"
        case .clipboardOnly:
            return "仅复制到剪贴板"
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
            return "横向卡片"
        case .vertical:
            return "纵向列表"
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
            return "1 天"
        case .week:
            return "1 周"
        case .month:
            return "1 个月"
        case .year:
            return "1 年"
        case .unlimited:
            return "永久"
        }
    }
}
