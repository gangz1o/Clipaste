import AppKit
import Foundation
import SwiftUI

extension ClipboardItem {
    // ⚠️ 等价性收窄：只比较"身份 + 易变标志"。
    // 1. `id` + `contentHash` 锁定身份；包含 contentHash 是因为编辑/迁移可能在同一
    //    UUID 下替换内容，UI 需要触发 diff。
    // 2. `timestamp` 反映置顶/重排序。
    // 3. 剩余字段是"会驱动 UI 重渲染"的可变标志（标题、链接元数据、固定、分组）。
    // 4. 大字段（linkIconData、rawText、fileDisplayPath 等）从比较和哈希中移除：
    //    这些要么由 id+contentHash 隐含锁定，要么会让 Published diff / Set / SwiftUI
    //    自带 .id() 路径在每次刷新时跑昂贵的字节级比较。
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.contentHash == rhs.contentHash &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isPinned == rhs.isPinned &&
        lhs.customTitle == rhs.customTitle &&
        lhs.linkTitle == rhs.linkTitle &&
        lhs.groupIDs == rhs.groupIDs &&
        lhs.hasRTF == rhs.hasRTF &&
        lhs.hasImagePreview == rhs.hasImagePreview &&
        lhs.hasImageData == rhs.hasImageData &&
        lhs.appIconDominantColorHex == rhs.appIconDominantColorHex
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(contentHash)
        hasher.combine(timestamp)
        hasher.combine(isPinned)
    }
}
