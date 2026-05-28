import AppKit
import SwiftUI

extension ClipboardViewModel {
    func handleSelection(id: UUID, isCommand: Bool, isShift: Bool) {
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
            requestListScroll(to: firstVisible.id, animated: false)
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
        requestListScroll(to: firstVisible.id, animated: false)
        prewarmQuickLookPreviewIfNeeded()
    }

    func selectFirstDisplayedItem(animatedScroll: Bool = false) {
        guard let firstVisible = displayedItemsForInteraction.first else {
            clearSelection()
            return
        }

        selectedItemIDs = [firstVisible.id]
        lastSelectedID = firstVisible.id
        requestListScroll(to: firstVisible.id, animated: animatedScroll)
        prewarmQuickLookPreviewIfNeeded()
    }

    func userDidSelect(item: ClipboardItem) {
        handleSelection(id: item.id, isCommand: false, isShift: false)
    }

    func moveSelection(direction: Int) {
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

        requestListScroll(to: nextID, animated: true)
        prewarmQuickLookPreviewIfNeeded()
    }

    var displayedItemsForInteraction: [ClipboardItem] {
        displayedItems
    }

    func selectionCandidateAfterRemoving(ids removedIDs: Set<UUID>) -> UUID? {
        let displayedItems = displayedItemsForInteraction
        guard let firstRemovedIndex = displayedItems.firstIndex(where: { removedIDs.contains($0.id) }) else {
            return nil
        }

        let remainingItems = displayedItems.filter { removedIDs.contains($0.id) == false }
        guard !remainingItems.isEmpty else {
            return nil
        }

        let candidateIndex = min(firstRemovedIndex, remainingItems.count - 1)
        return remainingItems[candidateIndex].id
    }

    func applySelectionAfterDeletion(
        fallbackID: UUID?,
        preservedSelectionIDs: Set<UUID> = []
    ) {
        let visibleIDs = Set(displayedItemsForInteraction.map(\.id))
        let remainingPreservedIDs = preservedSelectionIDs.intersection(visibleIDs)

        if !remainingPreservedIDs.isEmpty {
            selectedItemIDs = remainingPreservedIDs

            if let lastSelectedID, remainingPreservedIDs.contains(lastSelectedID) == false {
                self.lastSelectedID = displayedItemsForInteraction.first(where: {
                    remainingPreservedIDs.contains($0.id)
                })?.id
            } else if lastSelectedID == nil {
                self.lastSelectedID = displayedItemsForInteraction.first(where: {
                    remainingPreservedIDs.contains($0.id)
                })?.id
            }

            prewarmQuickLookPreviewIfNeeded()
            return
        }

        guard let fallbackID, visibleIDs.contains(fallbackID) else {
            clearSelection()
            return
        }

        selectedItemIDs = [fallbackID]
        lastSelectedID = fallbackID
        prewarmQuickLookPreviewIfNeeded()
    }

    func reconcileSelectionAfterDisplayedItemsChange() {
        if shouldResetSelectionToFirstDisplayedItem {
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
