import AppKit
import Foundation
import SwiftUI

enum VerticalFollowMode: String, CaseIterable, Identifiable {
    case statusBar = "statusBar"
    case mouse = "mouse"
    case lastPosition = "lastPosition"

    var id: String { self.rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .statusBar: return LocalizedStringResource("Near Status Bar Icon")
        case .mouse: return LocalizedStringResource("Near Mouse Cursor")
        case .lastPosition: return LocalizedStringResource("Last Position")
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case sixMonths = "6m"
    case oneYear = "1y"
    case unlimited = "unlimited"
    var id: String { self.rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .oneDay: return LocalizedStringResource("1 Day")
        case .threeDays: return LocalizedStringResource("3 Days")
        case .oneWeek: return LocalizedStringResource("1 Week")
        case .oneMonth: return LocalizedStringResource("1 Month")
        case .sixMonths: return LocalizedStringResource("6 Months")
        case .oneYear: return LocalizedStringResource("1 Year")
        case .unlimited: return LocalizedStringResource("Forever")
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
        case .oneDay:    return now.addingTimeInterval(-24 * 3600)
        case .threeDays:  return now.addingTimeInterval(-3 * 24 * 3600)
        case .oneWeek:    return now.addingTimeInterval(-7 * 24 * 3600)
        case .oneMonth:   return cal.date(byAdding: .month, value: -1, to: now)
        case .sixMonths:  return cal.date(byAdding: .month, value: -6, to: now)
        case .oneYear:    return cal.date(byAdding: .year,  value: -1, to: now)
        case .unlimited:  return nil
        }
    }
}
