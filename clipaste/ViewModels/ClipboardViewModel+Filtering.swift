import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func setupFilterPipeline() {
        performAsyncFilter(
            query: searchInput,
            items: items,
            groupId: selectedGroupId,
            typeFilter: currentFilter,
            builtInGroup: selectedBuiltInGroup
        )
    }

    func scheduleFilterForSearchInput() {
        searchDebounceTask?.cancel()
        let query = searchInput
        let isEffectivelyEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        searchDebounceTask = Task { [weak self] in
            if isEffectivelyEmpty == false {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard Task.isCancelled == false, let self else { return }
            self.activeSearchQuery = query
            self.performAsyncFilter(
                query: query,
                items: self.items,
                groupId: self.selectedGroupId,
                typeFilter: self.currentFilter,
                builtInGroup: self.selectedBuiltInGroup
            )
        }
    }

    func refreshFilterForDataOrScopeChange() {
        performAsyncFilter(
            query: activeSearchQuery,
            items: items,
            groupId: selectedGroupId,
            typeFilter: currentFilter,
            builtInGroup: selectedBuiltInGroup
        )
    }

    func performAsyncFilter(
        query: String,
        items: [ClipboardItem],
        groupId: String?,
        typeFilter: ClipboardContentType?,
        builtInGroup: ClipboardBuiltInGroup?
    ) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        filterTask?.cancel()
        filterGeneration &+= 1
        let thisGeneration = filterGeneration

        if cleanQuery.isEmpty && groupId == nil && typeFilter == nil && builtInGroup == nil {
            applyDisplayedItemIDsIfChanged(items.map(\.id))
            return
        }

        let shouldUseDatabaseSearch = !cleanQuery.isEmpty && hasLoadedFullHistory == false
        let snapshots = items.map { item in
            ClipboardFilterSnapshot(
                id: item.id,
                contentTypeRawValue: item.contentType.rawValue,
                groupIDs: item.groupIDs,
                isPinned: item.isPinned,
                searchableText: item.searchableText ?? item.rawText ?? item.textPreview,
                appName: item.appName
            )
        }

        filterTask = Task(priority: .userInitiated) { [weak self] in
            let result = await ClipboardFilterEngine.filteredIDs(
                snapshots: snapshots,
                query: cleanQuery,
                groupID: groupId,
                typeFilterRawValue: typeFilter?.rawValue,
                favoritesOnly: builtInGroup == .favorites
            )

            guard case let .completed(filteredIDs) = result,
                  Task.isCancelled == false,
                  let self,
                  self.filterGeneration == thisGeneration else { return }
            self.applyDisplayedItemIDsIfChanged(filteredIDs)

            guard shouldUseDatabaseSearch else { return }

            // 内存窗口外可能仍有匹配的历史记录 —— 派发一次 SQL 直查，
            // 把命中记录合并进 items 后追加到结果尾部。
            await self.runDatabaseSearchSupplement(
                query: cleanQuery,
                typeFilter: typeFilter,
                groupId: groupId,
                builtInGroup: builtInGroup,
                visibleIDs: filteredIDs,
                generation: thisGeneration
            )
        }
    }

    @MainActor
    private func runDatabaseSearchSupplement(
        query: String,
        typeFilter: ClipboardContentType?,
        groupId: String?,
        builtInGroup: ClipboardBuiltInGroup?,
        visibleIDs: [UUID],
        generation: UInt
    ) async {
        let storage = StorageManager.shared
        let dbResults = await storage.fetchItemsPage(
            searchText: query,
            fetchLimit: Self.databaseSearchPageSize,
            offset: 0
        )

        guard Task.isCancelled == false, filterGeneration == generation else { return }
        guard dbResults.isEmpty == false else { return }

        let scopedResults = dbResults.filter { item in
            if let typeFilter, item.contentType != typeFilter { return false }
            if let groupId, item.groupIDs.contains(groupId) == false { return false }
            if let builtInGroup, builtInGroup.matches(item) == false { return false }
            return true
        }

        let existingKeys = items.map {
            ClipboardItemDeduplicationKey(id: $0.id, contentHash: $0.contentHash)
        }
        let candidateKeys = scopedResults.map {
            ClipboardItemDeduplicationKey(id: $0.id, contentHash: $0.contentHash)
        }
        let acceptedIndexes = ClipboardItemDeduplicationPolicy.uniqueAppendIndexes(
            existing: existingKeys,
            incoming: candidateKeys
        )
        let newItems = acceptedIndexes.map { scopedResults[$0] }

        guard newItems.isEmpty == false else { return }
        guard Task.isCancelled == false, filterGeneration == generation else { return }

        mergeItems(newItems, prepend: false)
        applyDisplayedItemIDsIfChanged(visibleIDs + newItems.map(\.id))
    }

    private func applyDisplayedItemIDsIfChanged(_ newIDs: [UUID]) {
        guard displayedItemIDs != newIDs else { return }

        displayedItemIDs = newIDs
        reconcileSelectionAfterDisplayedItemsChange()
    }

}
