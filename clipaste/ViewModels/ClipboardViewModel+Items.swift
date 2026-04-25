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
        enqueueMissingLinkMetadata(for: newItems)
    }

    func mergeItems(_ incomingItems: [ClipboardItem], prepend: Bool) {
        guard !incomingItems.isEmpty else { return }

        let combined = prepend ? (incomingItems + items) : (items + incomingItems)
        let deduplicated = deduplicatedItemsPreservingOrder(combined)
        items = deduplicated
        rebuildItemIndexes()
        enqueueMissingLinkMetadata(for: incomingItems)
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
        enqueueMissingLinkMetadata(for: [item])
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

        if let selectedBuiltInGroup, selectedBuiltInGroup.matches(item) == false {
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

    func deduplicatedItemsPreservingOrder(_ sourceItems: [ClipboardItem]) -> [ClipboardItem] {
        var seenIDs: Set<UUID> = []
        var seenHashes: Set<String> = []
        var result: [ClipboardItem] = []
        result.reserveCapacity(sourceItems.count)

        for item in sourceItems {
            guard seenIDs.insert(item.id).inserted else { continue }
            guard seenHashes.insert(item.contentHash).inserted else { continue }
            result.append(item)
        }

        return result
    }

    func enqueueMissingLinkMetadata(for sourceItems: [ClipboardItem]) {
        let candidates = sourceItems
            .lazy
            .filter { $0.isFastLink && ($0.linkTitle == nil || $0.linkIconData == nil) }
            .prefix(24)

        for item in candidates {
            guard pendingLinkMetadataHashes.contains(item.contentHash) == false else { continue }

            let urlText = (item.rawText ?? item.previewText ?? item.textPreview)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard urlText.isEmpty == false else { continue }

            pendingLinkMetadataHashes.insert(item.contentHash)
            StorageManager.shared.processLinkMetadata(hash: item.contentHash, urlString: urlText)
        }
    }
}
