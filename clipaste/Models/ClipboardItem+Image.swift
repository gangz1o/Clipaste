import AppKit
import Foundation
import SwiftUI

extension ClipboardItem {
    nonisolated static func searchableTextValue(
        plainText: String?,
        customTitle: String?,
        linkTitle: String?
    ) -> String? {
        let candidates = [customTitle, plainText, linkTitle]
            .compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }

        guard candidates.isEmpty == false else {
            return nil
        }

        return candidates.joined(separator: "\n")
    }
}

// 计算属性已迁移至 init 中的存储属性，此处不再需要 extension
