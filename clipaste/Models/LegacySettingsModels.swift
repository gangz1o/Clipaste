import Foundation
import SwiftUI

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
    case compact = "Vertical Compact"

    var id: String { rawValue }

    /// Returns `true` for layouts that use a vertical list (`.vertical` and `.compact`).
    var isVertical: Bool {
        self == .vertical || self == .compact
    }

    var displayName: String {
        switch self {
        case .horizontal:
            return String(localized: "Horizontal Cards")
        case .vertical:
            return String(localized: "Vertical List")
        case .compact:
            return String(localized: "Vertical Compact")
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

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .day: return LocalizedStringResource("1 Day")
        case .week: return LocalizedStringResource("1 Week")
        case .month: return LocalizedStringResource("1 Month")
        case .year: return LocalizedStringResource("1 Year")
        case .unlimited: return LocalizedStringResource("Unlimited")
        }
    }
}
