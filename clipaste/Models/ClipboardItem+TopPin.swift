import Foundation

extension ClipboardItem {
    var isTopPinned: Bool { topPinOrder > 0 }

    nonisolated static func precedesInHistory(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.topPinOrder != rhs.topPinOrder {
            return lhs.topPinOrder > rhs.topPinOrder
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id < rhs.id
    }
}
