import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func setupFilterPipeline() {
        let searchQueries = $searchInput
            .map { query -> AnyPublisher<String, Never> in
                let isEffectivelyEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isEffectivelyEmpty {
                    return Just(query)
                        .eraseToAnyPublisher()
                }

                return Just(query)
                    .delay(for: .milliseconds(200), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()

        let dataChanges = Publishers.CombineLatest4($items, $selectedGroupId, $currentFilter, $selectedBuiltInGroup)

        Publishers.CombineLatest(searchQueries, dataChanges)
            .sink { [weak self] (query, quadruple) in
                guard let self else { return }
                let (allItems, groupId, filter, builtInGroup) = quadruple
                self.activeSearchQuery = query
                self.performAsyncFilter(
                    query: query,
                    items: allItems,
                    groupId: groupId,
                    typeFilter: filter,
                    builtInGroup: builtInGroup
                )
            }
            .store(in: &cancellables)
    }

    func performAsyncFilter(
        query: String,
        items: [ClipboardItem],
        groupId: String?,
        typeFilter: ClipboardContentType?,
        builtInGroup: ClipboardBuiltInGroup?
    ) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        filterGeneration &+= 1
        let thisGeneration = filterGeneration

        if cleanQuery.isEmpty && groupId == nil && typeFilter == nil && builtInGroup == nil {
            applyDisplayedItemIDsIfChanged(items.map(\.id))
            return
        }

        let shouldUseDatabaseSearch = !cleanQuery.isEmpty && hasLoadedFullHistory == false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let filteredIDs = items.compactMap { item -> UUID? in
                if let filter = typeFilter, item.contentType != filter {
                    return nil
                }

                if let gid = groupId, item.groupIDs.contains(gid) == false {
                    return nil
                }

                if let builtInGroup, builtInGroup.matches(item) == false {
                    return nil
                }

                if !cleanQuery.isEmpty {
                    let searchable = item.searchableText ?? item.rawText ?? item.textPreview
                    let matchesText = searchable.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    let matchesApp = item.appName.range(of: cleanQuery, options: [.caseInsensitive]) != nil

                    guard matchesText || matchesApp else {
                        return nil
                    }
                }

                return item.id
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.filterGeneration == thisGeneration else { return }
                self.applyDisplayedItemIDsIfChanged(filteredIDs)

                guard shouldUseDatabaseSearch else { return }

                // 内存窗口外可能仍有匹配的历史记录 —— 派发一次 SQL 直查，
                // 把命中记录合并进 items 后追加到结果尾部。
                self.runDatabaseSearchSupplement(
                    query: cleanQuery,
                    typeFilter: typeFilter,
                    groupId: groupId,
                    builtInGroup: builtInGroup,
                    visibleIDs: filteredIDs,
                    generation: thisGeneration
                )
            }
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
    ) {
        Task { [weak self] in
            guard let self else { return }

            let dbResults = await StorageManager.shared.fetchItemsPage(
                searchText: query,
                fetchLimit: Self.databaseSearchPageSize,
                offset: 0
            )

            guard self.filterGeneration == generation else { return }
            guard dbResults.isEmpty == false else { return }

            let scopedResults = dbResults.filter { item in
                if let typeFilter, item.contentType != typeFilter { return false }
                if let groupId, item.groupIDs.contains(groupId) == false { return false }
                if let builtInGroup, builtInGroup.matches(item) == false { return false }
                return true
            }

            let existingKeys = self.items.map {
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
            guard self.filterGeneration == generation else { return }

            self.mergeItems(newItems, prepend: false)
            self.applyDisplayedItemIDsIfChanged(visibleIDs + newItems.map(\.id))
        }
    }

    private func applyDisplayedItemIDsIfChanged(_ newIDs: [UUID]) {
        guard displayedItemIDs != newIDs else { return }

        displayedItemIDs = newIDs
        reconcileSelectionAfterDisplayedItemsChange()
    }

    func loadData(mode: DataLoadMode = .fullRefresh) {
        dataLoadGeneration &+= 1
        let generation = dataLoadGeneration
        historyLoadTask?.cancel()

        if items.isEmpty {
            isInitialHistoryLoading = true
        }

        // 读路径的优先级反转由 StorageManager.detachedRead 统一兜底,
        // 这里保持普通 MainActor Task 即可。
        historyLoadTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let firstPage = await StorageManager.shared.fetchItemsPage(
                searchText: "",
                fetchLimit: Self.initialVisibleItemBatchSize,
                offset: 0
            )

            guard !Task.isCancelled else { return }
            self.applyInitialHistoryPage(
                firstPage,
                generation: generation,
                mode: mode
            )

            guard firstPage.count == Self.initialVisibleItemBatchSize else {
                self.finishHistoryLoadingIfCurrent(generation: generation, loadedCount: firstPage.count)
                return
            }

            var offset = firstPage.count
            var totalLoaded = firstPage.count

            while !Task.isCancelled {
                // 内存窗口护栏：超过上限后停止后台分页，后续搜索走 SQL 直查路径，
                // 避免常驻数组无界增长导致的内存压力和搜索遍历放大。
                guard totalLoaded < Self.backgroundLoadMaxItems else {
                    self.finishHistoryLoadingIfCurrent(
                        generation: generation,
                        loadedCount: totalLoaded,
                        fullyLoaded: false
                    )
                    return
                }

                let remainingCap = Self.backgroundLoadMaxItems - totalLoaded
                let pageLimit = min(Self.backgroundPageBatchSize, remainingCap)

                let page = await StorageManager.shared.fetchItemsPage(
                    searchText: "",
                    fetchLimit: pageLimit,
                    offset: offset
                )

                guard !Task.isCancelled else { return }

                if page.isEmpty {
                    self.finishHistoryLoadingIfCurrent(generation: generation, loadedCount: totalLoaded)
                    return
                }

                totalLoaded += page.count
                offset += page.count
                self.appendHistoryPage(page, generation: generation, loadedCount: totalLoaded)

                if page.count < pageLimit {
                    self.finishHistoryLoadingIfCurrent(generation: generation, loadedCount: totalLoaded)
                    return
                }
            }
        }
    }

    func applyLoadedItems(_ mappedItems: [ClipboardItem]) {
        replaceItems(mappedItems)
        isInitialHistoryLoading = false

        // Keep displayedItemIDs in sync with the newly loaded items before
        // reconciling selection. Relying on the async filter pipeline alone can
        // leave one activation frame using the previous display order.
        refreshDisplayedItemsFromCurrentScope()

        if applyDeferredAutoSelectFirstItemIfNeeded() {
            return
        }

        let validIDs = Set(mappedItems.map(\.id))
        let staleIDs = selectedItemIDs.subtracting(validIDs)
        if !staleIDs.isEmpty {
            selectedItemIDs.subtract(staleIDs)
        }
        if let anchor = lastSelectedID, !validIDs.contains(anchor) {
            lastSelectedID = nil
        }

        reconcileSelectionAfterDisplayedItemsChange()
    }

    @MainActor
    func applyInitialHistoryPage(_ pageItems: [ClipboardItem], generation: UInt, mode: DataLoadMode) {
        guard generation == dataLoadGeneration else { return }

        if mode == .visibleFirst, items.isEmpty == false {
            mergeItems(pageItems, prepend: true)
            refreshDisplayedItemsFromCurrentScope()

            if applyDeferredAutoSelectFirstItemIfNeeded() {
                isInitialHistoryLoading = false
                isLoadingMoreHistory = pageItems.count == Self.initialVisibleItemBatchSize
                loadedHistoryCount = items.count
                hasLoadedFullHistory = pageItems.count < Self.initialVisibleItemBatchSize
                return
            }

            reconcileSelectionAfterDisplayedItemsChange()
        } else {
            applyLoadedItems(pageItems)
        }

        isInitialHistoryLoading = false
        isLoadingMoreHistory = pageItems.count == Self.initialVisibleItemBatchSize
        loadedHistoryCount = items.count
        hasLoadedFullHistory = pageItems.count < Self.initialVisibleItemBatchSize
    }

    @MainActor
    func appendHistoryPage(_ pageItems: [ClipboardItem], generation: UInt, loadedCount: Int) {
        guard generation == dataLoadGeneration else { return }

        mergeItems(pageItems, prepend: false)
        refreshDisplayedItemsFromCurrentScope()
        isInitialHistoryLoading = false
        isLoadingMoreHistory = true
        loadedHistoryCount = loadedCount
    }

    @MainActor
    func finishHistoryLoadingIfCurrent(generation: UInt, loadedCount: Int, fullyLoaded: Bool = true) {
        guard generation == dataLoadGeneration else { return }
        isInitialHistoryLoading = false
        isLoadingMoreHistory = false
        loadedHistoryCount = loadedCount
        // 内存窗口达到上限时 hasLoadedFullHistory 维持 false，让搜索路径知道
        // 需要回退到 SQL 直查；自然到达表尾时仍标记为 true。
        hasLoadedFullHistory = fullyLoaded
    }

    @discardableResult
    private func applyDeferredAutoSelectFirstItemIfNeeded() -> Bool {
        guard shouldAutoSelectFirstItemAfterNextRefresh else { return false }
        shouldAutoSelectFirstItemAfterNextRefresh = false

        guard displayedItemsForInteraction.isEmpty == false else {
            clearSelection()
            return true
        }

        selectFirstDisplayedItem()
        return true
    }
}
