import Foundation

extension ClipboardViewModel {
    func requestListScroll(to itemID: UUID, animated: Bool) {
        listScrollGeneration &+= 1
        listScrollRequest = ClipboardListScrollRequest(
            id: itemID,
            animated: animated,
            generation: listScrollGeneration
        )
    }

    func requestListScrollToPrimarySelection(animated: Bool) {
        guard let selectedID = lastSelectedID ?? selectedItemIDs.first else { return }
        requestListScroll(to: selectedID, animated: animated)
    }
}
