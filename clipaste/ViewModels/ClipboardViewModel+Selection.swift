import AppKit
import SwiftUI

extension ClipboardViewModel {
    func handleSelection(id: UUID, isCommand: Bool, isShift: Bool) {
        shouldAutoFollowTopItemDuringPresentation = false

        if isShift, let anchorID = lastSelectedID {
            let source = displayedItemsForInteraction
            if let anchorIdx = source.firstIndex(where: { $0.id == anchorID }),
               let targetIdx = source.firstIndex(where: { $0.id == id }) {
                let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
                let rangeIDs = Set(source[range].map(\.id))
                selectedItemIDs.formUnion(rangeIDs)
            }
        } else if isCommand {
            if selectedItemIDs.contains(id) {
                selectedItemIDs.remove(id)
            } else {
                selectedItemIDs.insert(id)
            }
            lastSelectedID = id
        } else {
            selectedItemIDs = [id]
            lastSelectedID = id
        }

        prewarmQuickLookPreviewIfNeeded()
    }

    func selectAll() {
        shouldAutoFollowTopItemDuringPresentation = false
        selectedItemIDs = Set(displayedItemsForInteraction.map(\.id))
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
        lastSelectedID = nil
    }

    func ensureListSelection() {
        guard let firstVisible = displayedItemsForInteraction.first else { return }

        if selectedItemIDs.isEmpty {
            selectedItemIDs = [firstVisible.id]
            lastSelectedID = firstVisible.id
            prewarmQuickLookPreviewIfNeeded()
            return
        }

        if let lastSelectedID,
           displayedItemsForInteraction.contains(where: { $0.id == lastSelectedID }),
           selectedItemIDs.contains(lastSelectedID) {
            return
        }

        if let selectedVisibleID = displayedItemsForInteraction.first(where: { selectedItemIDs.contains($0.id) })?.id {
            lastSelectedID = selectedVisibleID
            prewarmQuickLookPreviewIfNeeded()
            return
        }

        selectedItemIDs = [firstVisible.id]
        lastSelectedID = firstVisible.id
        prewarmQuickLookPreviewIfNeeded()
    }

    func selectFirstDisplayedItem() {
        guard let firstVisible = displayedItemsForInteraction.first else {
            clearSelection()
            return
        }

        selectedItemIDs = [firstVisible.id]
        lastSelectedID = firstVisible.id
        prewarmQuickLookPreviewIfNeeded()
    }

    func userDidSelect(item: ClipboardItem) {
        handleSelection(id: item.id, isCommand: false, isShift: false)
    }

    func moveSelection(direction: Int) {
        shouldAutoFollowTopItemDuringPresentation = false

        let displayedItems = displayedItemsForInteraction
        guard !displayedItems.isEmpty else { return }

        let currentIndex = lastSelectedID.flatMap { lid in
            displayedItems.firstIndex(where: { $0.id == lid })
        }

        let nextIndex: Int
        if let idx = currentIndex {
            nextIndex = min(max(idx + direction, 0), displayedItems.count - 1)
        } else {
            nextIndex = direction > 0 ? 0 : displayedItems.count - 1
        }

        let nextID = displayedItems[nextIndex].id
        withAnimation(.easeInOut(duration: 0.1)) {
            selectedItemIDs = [nextID]
            lastSelectedID = nextID
        }

        prewarmQuickLookPreviewIfNeeded()
    }

    var displayedItemsForInteraction: [ClipboardItem] {
        displayedItems
    }

    func reconcileSelectionAfterDisplayedItemsChange() {
        if shouldResetSelectionToFirstDisplayedItem || shouldAutoFollowTopItemDuringPresentation {
            shouldResetSelectionToFirstDisplayedItem = false
            selectFirstDisplayedItem()
            return
        }

        clampSelectionToDisplayedItems()
    }

    func clampSelectionToDisplayedItems() {
        let visibleIDs = Set(displayedItemsForInteraction.map(\.id))

        if !selectedItemIDs.isSubset(of: visibleIDs) {
            selectedItemIDs.formIntersection(visibleIDs)
        }

        if let lastSelectedID, !visibleIDs.contains(lastSelectedID) {
            self.lastSelectedID = selectedItemIDs.first
        }

        if let quickLookItem, !visibleIDs.contains(quickLookItem.id) {
            dismissQuickLook()
        }
    }
}
