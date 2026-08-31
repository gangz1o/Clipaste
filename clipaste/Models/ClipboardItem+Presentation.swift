import AppKit
import Foundation
import SwiftUI

extension ClipboardItem {
    /// 卡片角标等内容类型文案（与筛选标签共用同一套 String Catalog 键）。
    @MainActor
    func typeBadgeTitle() -> LocalizedStringResource {
        switch contentType {
        case .text: return LocalizedStringResource("Smart Filter Text")
        case .image: return LocalizedStringResource("Smart Filter Image")
        case .fileURL: return LocalizedStringResource("Smart Filter File")
        case .color: return LocalizedStringResource("Smart Filter Color")
        case .link: return LocalizedStringResource("Smart Filter Link")
        case .code: return LocalizedStringResource("Smart Filter Code")
        }
    }

    var groupId: String? {
        groupIDs.first
    }

    var trimmedCustomTitle: String? {
        let normalized = customTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, normalized.isEmpty == false else {
            return nil
        }
        return normalized
    }

    var hasCustomTitle: Bool {
        trimmedCustomTitle != nil
    }

    var imagePixelSize: CGSize? {
        guard let imagePixelWidth, let imagePixelHeight else { return nil }
        guard imagePixelWidth > 0, imagePixelHeight > 0 else { return nil }
        return CGSize(width: imagePixelWidth, height: imagePixelHeight)
    }

    var isScreenPinEligible: Bool {
        contentType == .image || (contentType == .fileURL && fileRepresentsImage)
    }

    nonisolated static func normalizedGroupIDs(primaryGroupID: String?, groupIDs: [String]) -> [String] {
        var result: [String] = []

        if let primaryGroupID, !primaryGroupID.isEmpty {
            result.append(primaryGroupID)
        }

        for id in groupIDs where !id.isEmpty && result.contains(id) == false {
            result.append(id)
        }

        return result
    }
}
