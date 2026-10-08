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
            applyDisplayedItemIDsIfChanged(items.filter(isWithinLoadedHistoryWindow).map(\.id))
            return
        }

        let shouldUseDatabaseSearch = !cleanQuery.isEmpty && hasLoadedFullHistory == false
        // 分组 / 收藏 / 类型筛选只在内存窗口里过滤时，窗口外的旧成员会整体缺失；
        // 结果为空时列表也没有条目能触发继续加载，所以按范围直查数据库补齐一次。
        let scopeKey = ScopeSupplementKey(
            groupId: groupId,
            typeRawValue: typeFilter?.rawValue,
            favoritesOnly: builtInGroup == .favorites
        )
        let shouldUseScopeSupplement = cleanQuery.isEmpty
            && hasLoadedFullHistory == false
            && completedScopeSupplementKey != scopeKey
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

            if shouldUseScopeSupplement {
                await self.runScopeSupplement(
                    key: scopeKey,
                    typeFilter: typeFilter,
                    groupId: groupId,
                    builtInGroup: builtInGroup,
                    generation: thisGeneration
                )
                return
            }

            guard shouldUseDatabaseSearch else { return }

            // 内存窗口外可能仍有匹配的历史记录 —— 派发一次 SQL 直查，
            // 把命中记录合并进 items 后追加到结果尾部。
            await self.runDatabaseSearchSupplement(
                query: cleanQuery,
                typeFilter: typeFilter,
                groupId: groupId,
                builtInGroup: builtInGroup,
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
        generation: UInt
    ) async {
        // 带筛选范围时把范围一起下推到 SQL：否则先取全库前 200 条命中再按范围筛，
        // 范围内较旧的命中会被挤出这 200 条而搜不到。
        let storage = StorageManager.shared
        let hasScope = groupId != nil || typeFilter != nil || builtInGroup != nil
        let dbResults = hasScope
            ? await storage.fetchScopedItems(
                searchText: query,
                groupId: groupId,
                typeRawValue: typeFilter?.rawValue,
                favoritesOnly: builtInGroup == .favorites,
                fetchLimit: Self.databaseSearchPageSize
            )
            : await storage.fetchItemsPage(
                searchText: query,
                fetchLimit: Self.databaseSearchPageSize,
                offset: 0
            )

        guard Task.isCancelled == false, filterGeneration == generation else { return }
        mergeSupplementResults(
            dbResults,
            typeFilter: typeFilter,
            groupId: groupId,
            builtInGroup: builtInGroup
        )
    }

    @MainActor
    private func runScopeSupplement(
        key: ScopeSupplementKey,
        typeFilter: ClipboardContentType?,
        groupId: String?,
        builtInGroup: ClipboardBuiltInGroup?,
        generation: UInt
    ) async {
        let dbResults = await StorageManager.shared.fetchScopedItems(
            groupId: groupId,
            typeRawValue: typeFilter?.rawValue,
            favoritesOnly: builtInGroup == .favorites,
            fetchLimit: Self.scopedFetchLimit
        )

        guard Task.isCancelled == false, filterGeneration == generation else { return }
        // 先记下再合并：合并会改 items 并同步触发一次重新过滤，那次过滤不应再查库。
        completedScopeSupplementKey = key
        mergeSupplementResults(
            dbResults,
            typeFilter: typeFilter,
            groupId: groupId,
            builtInGroup: builtInGroup
        )
    }

    /// 把数据库补齐结果按当前范围取交集、去重后合并进 items。
    private func mergeSupplementResults(
        _ dbResults: [ClipboardItem],
        typeFilter: ClipboardContentType?,
        groupId: String?,
        builtInGroup: ClipboardBuiltInGroup?
    ) {
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

        mergeItems(newItems, prepend: false)
        refreshDisplayedItemsFromCurrentScope()
    }

    private func applyDisplayedItemIDsIfChanged(_ newIDs: [UUID]) {
        guard displayedItemIDs != newIDs else { return }

        displayedItemIDs = newIDs
        reconcileSelectionAfterDisplayedItemsChange()
    }

}
