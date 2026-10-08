import Foundation

extension ClipboardViewModel {
    func toggleTopPin(item: ClipboardItem) {
        let order = item.isTopPinned ? 0 : Date().timeIntervalSince1970
        StorageManager.shared.setTopPin(hash: item.contentHash, order: order)
    }
}
