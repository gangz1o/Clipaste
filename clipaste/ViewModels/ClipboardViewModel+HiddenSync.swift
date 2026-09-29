import Combine
import Foundation

enum HiddenFirstPagePrefetchPhase {
    case idle
    case debouncing
    case fetching
}

/// 面板隐藏期间的增量同步，目标是呼出即最新。
///
/// 隐藏时绝不修改被观察的状态（items / displayedItemIDs / selection）：已 orderOut 的
/// hosting view 仍会因此重算 body 与布局，并连带触发滚动、自动预览等 onChange，
/// 这正是空闲布局循环一类回归的来源。这里只在后台取快照放进 @ObservationIgnored
/// 的暂存区，由 showPanel 同步发出的 willPresent 在首帧之前一次性合并。
extension ClipboardViewModel {
    /// 暂存条数上限，超过后改为预取首屏整页，批量变更时比逐条取快照更省。
    static let hiddenStagedChangeLimit = 64
    static let hiddenFirstPagePrefetchDelay: Duration = .milliseconds(300)

    func setupPanelWillPresentSubscription() {
        // 不能 receive(on:)：通知由 showPanel 在主线程同步发出，异步处理就赶不上首帧。
        NotificationCenter.default.publisher(for: .clipboardPanelWillPresent)
            .sink { [weak self] _ in
                self?.applyHiddenChangesBeforePresentation()
            }
            .store(in: &cancellables)
    }

    func stageHiddenRecordChange(_ change: ClipboardRecordChange) {
        // 整页预取尚未开始读库：这次变更必然会被读进去，不必再单独取快照。
        guard hiddenFirstPagePrefetchPhase != .debouncing else { return }

        let contentHash = change.contentHash
        // 补全/内容类变更只关心已在列表里的记录；列表外的旧记录插进来会在窗口中间凭空多出一条。
        if change.kind == .enrichment || change.kind == .content,
           itemIndexByHash[contentHash] == nil,
           hiddenStagedUpserts[contentHash] == nil {
            return
        }

        hiddenChangeSequence &+= 1
        let sequence = hiddenChangeSequence
        hiddenChangeSequenceByHash[contentHash] = sequence

        guard change.kind != .delete else {
            stageHiddenDelete(contentHash)
            return
        }

        Task { @MainActor [weak self] in
            let item = await StorageManager.shared.fetchItem(hash: contentHash)
            // 同一条记录又有更新的变更，或整页预取已接管，丢弃这份旧快照。
            guard let self, self.hiddenChangeSequenceByHash[contentHash] == sequence else { return }
            self.hiddenChangeSequenceByHash.removeValue(forKey: contentHash)

            guard self.isPanelPresentationActive == false else {
                // 取快照期间面板已经呼出，按可见路径合并。
                if let item {
                    self.applyStoreRecordChanges(
                        upserts: [item],
                        deletedHashes: [],
                        followsTopInsertion: change.kind == .upsert
                    )
                } else {
                    self.loadData()
                }
                return
            }

            guard let item else {
                self.scheduleHiddenFirstPagePrefetch()
                return
            }
            self.stageHiddenUpsert(item)
        }
    }

    /// 批量变更（远端同步、保留期清理、路由切换等）：隐藏时预取首屏整页，不在呼出时现查。
    func scheduleHiddenFirstPagePrefetch() {
        // 预取落地前被呼出时，beginPresentation 走整页刷新兜底。
        needsReloadOnNextPresentation = true
        hiddenPrefetchedFirstPage = nil

        switch hiddenFirstPagePrefetchPhase {
        case .debouncing:
            return
        case .fetching:
            // 在读库途中的这份结果不一定包含本次变更，重来一次。
            hiddenFirstPagePrefetchTask?.cancel()
        case .idle:
            break
        }

        hiddenFirstPagePrefetchPhase = .debouncing
        hiddenFirstPagePrefetchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hiddenFirstPagePrefetchDelay)
            guard let self, Task.isCancelled == false else { return }

            // 从这里开始读到的首屏已包含此前的所有变更；之后到达的变更照常逐条暂存。
            self.hiddenFirstPagePrefetchPhase = .fetching
            self.hiddenStagedUpserts.removeAll()
            self.hiddenStagedDeletes.removeAll()
            self.hiddenChangeSequenceByHash.removeAll()

            let page = await StorageManager.shared.fetchItemsPage(
                searchText: "",
                fetchLimit: Self.initialVisibleItemBatchSize
            )
            guard Task.isCancelled == false else { return }

            self.hiddenFirstPagePrefetchPhase = .idle
            self.hiddenFirstPagePrefetchTask = nil
            guard self.isPanelPresentationActive == false else { return }
            self.hiddenPrefetchedFirstPage = page
            self.needsReloadOnNextPresentation = false
        }
    }

    /// 首帧之前把隐藏期间的变更一次性合并进列表。beginPresentation 会再调用一次，
    /// 补上 willPresent 之后到面板成为 key 之间落地的快照。
    func applyHiddenChangesBeforePresentation() {
        guard hasPreparedPanelData, isPanelPresentationActive == false else { return }

        if needsGroupReloadOnNextPresentation {
            needsGroupReloadOnNextPresentation = false
            loadCustomGroups()
        }

        if let page = hiddenPrefetchedFirstPage {
            hiddenPrefetchedFirstPage = nil
            // 与 beginPresentation 的整页刷新语义一致，同时作废仍在途的旧加载。
            historyLoadTask?.cancel()
            dataLoadGeneration &+= 1
            shouldResetSelectionToFirstDisplayedItem = true
            shouldAutoSelectFirstItemAfterNextRefresh = settingsViewModel.autoFocusFirstItemOnPanelActivation
            applyInitialHistoryPage(page, generation: dataLoadGeneration, mode: .fullRefresh)
        }

        guard needsReloadOnNextPresentation == false else {
            // 整页预取没赶上或需要完整重载：交给 beginPresentation 整页刷新，暂存作废。
            discardHiddenStaging()
            return
        }

        guard hiddenStagedUpserts.isEmpty == false || hiddenStagedDeletes.isEmpty == false else { return }
        let upserts = Array(hiddenStagedUpserts.values)
        let deletedHashes = hiddenStagedDeletes
        hiddenStagedUpserts.removeAll()
        hiddenStagedDeletes.removeAll()
        applyStoreRecordChanges(upserts: upserts, deletedHashes: deletedHashes, followsTopInsertion: true)
    }

    func discardHiddenStaging() {
        hiddenFirstPagePrefetchTask?.cancel()
        hiddenFirstPagePrefetchTask = nil
        hiddenFirstPagePrefetchPhase = .idle
        hiddenPrefetchedFirstPage = nil
        hiddenStagedUpserts.removeAll()
        hiddenStagedDeletes.removeAll()
        hiddenChangeSequenceByHash.removeAll()
    }

    private func stageHiddenUpsert(_ item: ClipboardItem) {
        hiddenStagedDeletes.remove(item.contentHash)
        hiddenStagedUpserts[item.contentHash] = item
        collapseHiddenStagingIfNeeded()
    }

    private func stageHiddenDelete(_ contentHash: String) {
        hiddenStagedUpserts.removeValue(forKey: contentHash)
        hiddenStagedDeletes.insert(contentHash)
        collapseHiddenStagingIfNeeded()
    }

    private func collapseHiddenStagingIfNeeded() {
        guard hiddenStagedUpserts.count + hiddenStagedDeletes.count > Self.hiddenStagedChangeLimit else { return }
        scheduleHiddenFirstPagePrefetch()
    }
}
