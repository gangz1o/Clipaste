import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func loadData(mode: DataLoadMode = .fullRefresh) {
        dataLoadGeneration &+= 1
        let generation = dataLoadGeneration
        historyLoadTask?.cancel()
        isInitialHistoryPageLoadInFlight = true
        storeUpsertsDuringHistoryLoad.removeAll()
        storeDeletesDuringHistoryLoad.removeAll()
        let shouldDeferRefreshUntilAfterPresentation = mode == .visibleFirst && items.isEmpty == false

        if items.isEmpty {
            isInitialHistoryLoading = true
        }

        // 读路径的优先级反转由 StorageManager.detachedRead 统一兜底,
        // 这里保持普通 MainActor Task 即可。
        historyLoadTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            if shouldDeferRefreshUntilAfterPresentation {
                try? await Task.sleep(for: .milliseconds(160))
                guard Task.isCancelled == false else { return }
            }

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
        }
    }

    func loadMoreHistoryIfNeeded(currentItemID: UUID) async {
        guard isPanelPresentationActive else { return }
        guard isLoadingMoreHistory == false, hasLoadedFullHistory == false else { return }
        guard loadedHistoryCount < Self.backgroundLoadMaxItems else { return }
        guard let visibleIndex = displayedItemIDs.firstIndex(of: currentItemID) else { return }
        guard visibleIndex >= max(displayedItemIDs.count - 12, 0) else { return }

        let generation = dataLoadGeneration
        let offset = loadedHistoryCount
        let pageLimit = min(
            Self.backgroundPageBatchSize,
            Self.backgroundLoadMaxItems - loadedHistoryCount
        )
        isLoadingMoreHistory = true
        defer {
            if generation == dataLoadGeneration {
                isLoadingMoreHistory = false
            }
        }

        let page = await StorageManager.shared.fetchItemsPage(
            searchText: "",
            fetchLimit: pageLimit,
            offset: offset
        )

        guard Task.isCancelled == false, generation == dataLoadGeneration else { return }
        guard page.isEmpty == false else {
            hasLoadedFullHistory = true
            historyWindowBoundary = nil
            refreshDisplayedItemsFromCurrentScope()
            return
        }

        let totalLoaded = offset + page.count
        appendHistoryPage(
            page,
            generation: generation,
            loadedCount: totalLoaded,
            isComplete: page.count < pageLimit
        )
    }

    func trimHistoryWindowForIdleIfNeeded() {
        guard activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard currentFilter == nil, selectedBuiltInGroup == nil, selectedGroupId == nil else { return }
        guard items.count > Self.initialVisibleItemBatchSize else { return }

        historyLoadTask?.cancel()
        dataLoadGeneration &+= 1
        endInitialHistoryPageLoadTracking()
        let retainedItems = Array(
            items.lazy.filter(isWithinLoadedHistoryWindow).prefix(Self.initialVisibleItemBatchSize)
        )
        hasLoadedFullHistory = false
        updateHistoryWindowBoundary(loadedPage: retainedItems, isComplete: false, extendsCurrentWindow: false)
        replaceItems(retainedItems)
        refreshDisplayedItemsFromCurrentScope()
        loadedHistoryCount = retainedItems.count
        isLoadingMoreHistory = false
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
    func applyInitialHistoryPage(_ fetchedPageItems: [ClipboardItem], generation: UInt, mode: DataLoadMode) {
        guard generation == dataLoadGeneration else { return }
        let fetchedPageCount = fetchedPageItems.count
        let pageItems = mergingStoreChangesDuringHistoryLoad(into: fetchedPageItems)
        endInitialHistoryPageLoadTracking()

        // 先更新载入状态再改 items：items 的 didSet 会同步重新过滤，
        // 过滤据此决定是否需要范围补齐、「全部」视图展示到哪里。
        let isComplete = fetchedPageCount < Self.initialVisibleItemBatchSize
        let extendsCurrentWindow = mode == .visibleFirst && items.isEmpty == false
        hasLoadedFullHistory = isComplete
        updateHistoryWindowBoundary(
            loadedPage: fetchedPageItems,
            isComplete: isComplete,
            extendsCurrentWindow: extendsCurrentWindow
        )

        var mergedLoadedHistoryCount: Int?
        if extendsCurrentWindow {
            // items 里可能混有搜索 / 范围补齐进来的窗口外记录，不能直接用 items.count
            // 当作分页 offset，否则继续加载会跳过一段历史。只累加本次新并入的条目。
            let countBeforeMerge = items.count
            mergeItems(pageItems, prepend: true)
            refreshDisplayedItemsFromCurrentScope()
            mergedLoadedHistoryCount = max(
                loadedHistoryCount + (items.count - countBeforeMerge),
                fetchedPageCount
            )

            if applyDeferredAutoSelectFirstItemIfNeeded() {
                isInitialHistoryLoading = false
                isLoadingMoreHistory = false
                loadedHistoryCount = mergedLoadedHistoryCount ?? items.count
                return
            }

            reconcileSelectionAfterDisplayedItemsChange()
        } else {
            applyLoadedItems(pageItems)
        }

        isInitialHistoryLoading = false
        isLoadingMoreHistory = false
        loadedHistoryCount = mergedLoadedHistoryCount ?? items.count
    }

    @MainActor
    func appendHistoryPage(
        _ pageItems: [ClipboardItem],
        generation: UInt,
        loadedCount: Int,
        isComplete: Bool
    ) {
        guard generation == dataLoadGeneration else { return }

        hasLoadedFullHistory = isComplete
        updateHistoryWindowBoundary(loadedPage: pageItems, isComplete: isComplete, extendsCurrentWindow: true)
        mergeItems(pageItems, prepend: false)
        refreshDisplayedItemsFromCurrentScope()
        isInitialHistoryLoading = false
        loadedHistoryCount = loadedCount
    }

    func recordStoreChangeDuringHistoryLoad(upserted item: ClipboardItem) {
        guard isInitialHistoryPageLoadInFlight else { return }
        storeDeletesDuringHistoryLoad.remove(item.contentHash)
        storeUpsertsDuringHistoryLoad[item.contentHash] = item
    }

    func recordStoreChangeDuringHistoryLoad(deletedHash contentHash: String) {
        guard isInitialHistoryPageLoadInFlight else { return }
        storeUpsertsDuringHistoryLoad.removeValue(forKey: contentHash)
        storeDeletesDuringHistoryLoad.insert(contentHash)
    }

    private func endInitialHistoryPageLoadTracking() {
        isInitialHistoryPageLoadInFlight = false
        storeUpsertsDuringHistoryLoad.removeAll()
        storeDeletesDuringHistoryLoad.removeAll()
    }

    private func mergingStoreChangesDuringHistoryLoad(into pageItems: [ClipboardItem]) -> [ClipboardItem] {
        guard storeUpsertsDuringHistoryLoad.isEmpty == false || storeDeletesDuringHistoryLoad.isEmpty == false else {
            return pageItems
        }

        let changedHashes = storeDeletesDuringHistoryLoad.union(storeUpsertsDuringHistoryLoad.keys)
        var merged = pageItems.filter { changedHashes.contains($0.contentHash) == false }
        merged.append(contentsOf: storeUpsertsDuringHistoryLoad.values)
        merged.sort(by: ClipboardItem.precedesInHistory)
        return merged
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
