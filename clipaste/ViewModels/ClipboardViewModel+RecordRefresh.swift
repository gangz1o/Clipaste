import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func setupRecordChangeSubscriptions() {
        NotificationCenter.default.publisher(for: .clipboardRecordDidChange)
            .compactMap(\.clipboardRecordChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self, self.hasPreparedPanelData else { return }
                guard self.isPanelPresentationActive else {
                    self.stageHiddenRecordChange(change)
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.refreshRecordAfterStoreChange(change)
                }
            }
            .store(in: &cancellables)
    }

    func refreshRecordAfterStoreChange(_ change: ClipboardRecordChange) async {
        if change.kind == .delete {
            applyStoreRecordChanges(upserts: [], deletedHashes: [change.contentHash])
            return
        }

        guard let item = await StorageManager.shared.fetchItem(hash: change.contentHash) else {
            loadData()
            return
        }

        applyStoreRecordChanges(
            upserts: [item],
            deletedHashes: [],
            shouldResort: change.kind.requiresResort,
            followsTopInsertion: change.kind == .upsert
        )
    }

    /// 把已取好快照的变更合并进列表。可见时的增量刷新和呼出前合并隐藏期暂存都走这里。
    func applyStoreRecordChanges(
        upserts: [ClipboardItem],
        deletedHashes: Set<String>,
        shouldResort: Bool = true,
        followsTopInsertion: Bool = false
    ) {
        let previousFirstVisibleID = displayedItemsForInteraction.first?.id
        let shouldFollowTopInsertion =
            followsTopInsertion &&
            upserts.isEmpty == false &&
            selectedItemIDs.count == 1 &&
            previousFirstVisibleID != nil &&
            selectedItemIDs.contains(previousFirstVisibleID!) &&
            lastSelectedID == previousFirstVisibleID

        for contentHash in deletedHashes {
            recordStoreChangeDuringHistoryLoad(deletedHash: contentHash)
        }
        removeItems(withHashes: deletedHashes)

        for item in upserts {
            recordStoreChangeDuringHistoryLoad(upserted: item)
        }
        upsertItems(upserts, shouldResort: shouldResort)

        reconcileSelectionAfterDisplayedItemsChange()

        if shouldFollowTopInsertion,
           let previousFirstVisibleID,
           displayedItemsForInteraction.first?.id != previousFirstVisibleID {
            selectFirstDisplayedItem()
        }
    }
}

private extension ClipboardRecordChangeKind {
    var requiresResort: Bool {
        switch self {
        case .upsert, .reorder:
            return true
        case .enrichment, .content, .delete:
            return false
        }
    }
}
