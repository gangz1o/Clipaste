import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func loadData(mode: DataLoadMode = .fullRefresh) {
        dataLoadGeneration &+= 1
        let generation = dataLoadGeneration
        historyLoadTask?.cancel()
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
            return
        }

        let totalLoaded = offset + page.count
        appendHistoryPage(page, generation: generation, loadedCount: totalLoaded)
        hasLoadedFullHistory = page.count < pageLimit
    }

    func trimHistoryWindowForIdleIfNeeded() {
        guard activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard currentFilter == nil, selectedBuiltInGroup == nil, selectedGroupId == nil else { return }
        guard items.count > Self.initialVisibleItemBatchSize else { return }

        historyLoadTask?.cancel()
        dataLoadGeneration &+= 1
        let retainedItems = Array(items.prefix(Self.initialVisibleItemBatchSize))
        replaceItems(retainedItems)
        refreshDisplayedItemsFromCurrentScope()
        loadedHistoryCount = retainedItems.count
        hasLoadedFullHistory = false
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
    func applyInitialHistoryPage(_ pageItems: [ClipboardItem], generation: UInt, mode: DataLoadMode) {
        guard generation == dataLoadGeneration else { return }

        if mode == .visibleFirst, items.isEmpty == false {
            mergeItems(pageItems, prepend: true)
            refreshDisplayedItemsFromCurrentScope()

            if applyDeferredAutoSelectFirstItemIfNeeded() {
                isInitialHistoryLoading = false
                isLoadingMoreHistory = false
                loadedHistoryCount = items.count
                hasLoadedFullHistory = pageItems.count < Self.initialVisibleItemBatchSize
                return
            }

            reconcileSelectionAfterDisplayedItemsChange()
        } else {
            applyLoadedItems(pageItems)
        }

        isInitialHistoryLoading = false
        isLoadingMoreHistory = false
        loadedHistoryCount = items.count
        hasLoadedFullHistory = pageItems.count < Self.initialVisibleItemBatchSize
    }

    @MainActor
    func appendHistoryPage(_ pageItems: [ClipboardItem], generation: UInt, loadedCount: Int) {
        guard generation == dataLoadGeneration else { return }

        mergeItems(pageItems, prepend: false)
        refreshDisplayedItemsFromCurrentScope()
        isInitialHistoryLoading = false
        loadedHistoryCount = loadedCount
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
