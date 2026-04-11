import AppKit
import SwiftUI

extension ClipboardViewModel {
    var displayedItems: [ClipboardItem] {
        displayedItemIDs.compactMap(item(for:))
    }

    func item(for id: UUID) -> ClipboardItem? {
        guard let index = itemIndexByID[id], items.indices.contains(index) else {
            return nil
        }

        return items[index]
    }

    @discardableResult
    func updateItem(id: UUID, _ mutate: (inout ClipboardItem) -> Void) -> Bool {
        guard let index = itemIndexByID[id], items.indices.contains(index) else {
            return false
        }

        mutate(&items[index])
        refreshDisplayedItemsFromCurrentScope()
        return true
    }

    func replaceItems(_ newItems: [ClipboardItem]) {
        items = newItems
        rebuildItemIndexes()
    }

    func removeItems(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        items.removeAll { ids.contains($0.id) }
        refreshDisplayedItemsFromCurrentScope()
        rebuildItemIndexes()
    }

    func removeItem(withHash contentHash: String) {
        guard let index = itemIndexByHash[contentHash], items.indices.contains(index) else {
            return
        }

        items.remove(at: index)
        refreshDisplayedItemsFromCurrentScope()
        rebuildItemIndexes()
    }

    func moveItem(withID id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = itemIndexByID[id], items.indices.contains(sourceIndex) else {
            return
        }

        let boundedDestination = min(max(destinationIndex, 0), items.count - 1)
        guard sourceIndex != boundedDestination else { return }

        let movedItem = items.remove(at: sourceIndex)
        items.insert(movedItem, at: boundedDestination)
        refreshDisplayedItemsFromCurrentScope()
        rebuildItemIndexes()
    }

    func upsertItem(_ item: ClipboardItem, shouldResort: Bool) {
        if let index = itemIndexByHash[item.contentHash], items.indices.contains(index) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }

        if shouldResort {
            sortItemsByPresentationOrder()
        }

        refreshDisplayedItemsFromCurrentScope()
        rebuildItemIndexes()
    }
}

extension ClipboardViewModel {
    func refreshDisplayedItemsFromCurrentScope() {
        let query = activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        displayedItemIDs = items.compactMap { item in
            guard matchesCurrentDisplayScope(item, query: query) else {
                return nil
            }

            return item.id
        }
    }
}

private extension ClipboardViewModel {
    func rebuildItemIndexes() {
        var idIndex: [UUID: Int] = [:]
        var hashIndex: [String: Int] = [:]
        idIndex.reserveCapacity(items.count)
        hashIndex.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            idIndex[item.id] = offset
            hashIndex[item.contentHash] = offset
        }

        itemIndexByID = idIndex
        itemIndexByHash = hashIndex
    }

    func sortItemsByPresentationOrder() {
        items.sort { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    func matchesCurrentDisplayScope(_ item: ClipboardItem, query: String) -> Bool {
        if let currentFilter, item.contentType != currentFilter {
            return false
        }

        if let selectedGroupId, item.groupIDs.contains(selectedGroupId) == false {
            return false
        }

        guard !query.isEmpty else {
            return true
        }

        let searchable = item.searchableText ?? item.rawText ?? item.textPreview
        if searchable.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        return item.appName.range(of: query, options: [.caseInsensitive]) != nil
    }
}
