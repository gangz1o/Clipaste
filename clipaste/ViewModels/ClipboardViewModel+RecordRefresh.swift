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
                    self.needsReloadOnNextPresentation = true
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.refreshRecordAfterStoreChange(change)
                }
            }
            .store(in: &cancellables)
    }

    func refreshRecordAfterStoreChange(_ change: ClipboardRecordChange) async {
        let previousFirstVisibleID = displayedItemsForInteraction.first?.id
        let shouldFollowTopInsertion =
            change.kind == .upsert &&
            selectedItemIDs.count == 1 &&
            previousFirstVisibleID != nil &&
            selectedItemIDs.contains(previousFirstVisibleID!) &&
            lastSelectedID == previousFirstVisibleID

        if change.kind == .delete {
            removeItem(withHash: change.contentHash)
            reconcileSelectionAfterDisplayedItemsChange()
            return
        }

        guard let item = await StorageManager.shared.fetchItem(hash: change.contentHash) else {
            loadData()
            return
        }

        upsertItem(item, shouldResort: change.kind.requiresResort)
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
