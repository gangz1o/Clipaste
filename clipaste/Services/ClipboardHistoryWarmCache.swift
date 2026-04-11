import Foundation

actor ClipboardHistoryWarmCache {
    static let shared = ClipboardHistoryWarmCache()
    static let defaultLimit = 80

    private var routeKey: String?
    private var items: [ClipboardItem] = []

    func update(items: [ClipboardItem], routeKey: String) {
        self.routeKey = routeKey
        self.items = items
    }

    func snapshot(for routeKey: String) -> [ClipboardItem]? {
        guard self.routeKey == routeKey, items.isEmpty == false else {
            return nil
        }

        return items
    }

    func clear() {
        routeKey = nil
        items = []
    }
}

extension Notification.Name {
    static let clipboardWarmCacheDidChange = Notification.Name("clipboardWarmCacheDidChange")
}

struct ClipboardWarmCacheChange: Sendable {
    let routeKey: String
}

extension Notification {
    var clipboardWarmCacheChange: ClipboardWarmCacheChange? {
        guard name == .clipboardWarmCacheDidChange,
              let routeKey = userInfo?["routeKey"] as? String else {
            return nil
        }

        return ClipboardWarmCacheChange(routeKey: routeKey)
    }
}
