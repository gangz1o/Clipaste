import AppKit
import SwiftUI

extension ClipboardViewModel {
    func pasteToActiveApp(item: ClipboardItem) {
        if suppressedPasteItemIDs.remove(item.id) != nil {
            return
        }

        selectedItemIDs = [item.id]
        lastSelectedID = item.id

        Task { @MainActor in
            guard let record = await pasteRecord(for: item) else {
                return
            }

            let wroteToPasteboard = await PasteEngine.shared.writeToPasteboard(
                record: record,
                preferPlainText: shouldForcePlainTextOutput
            )
            guard wroteToPasteboard else {
                return
            }

            ClipboardPanelManager.shared.forceHidePanel()

            let autoPaste = UserDefaults.standard.object(forKey: "autoPasteToActiveApp") as? Bool ?? true
            if autoPaste {
                guard PasteEngine.shared.checkAccessibilityPermissions() else {
                    return
                }

                Task { @MainActor in
                    try? await Task.sleep(for: PasteEngine.postHidePasteDelay)
                    PasteEngine.shared.simulateCommandV()
                }
            }

            moveItemToTopIfPreferred(item)
        }
    }

    func pasteAsPlainText(item: ClipboardItem) {
        Task { @MainActor in
            guard let text = await plainText(for: item) else { return }
            PasteEngine.shared.writePlainTextToPasteboard(text: text)
            ClipboardPanelManager.shared.forceHidePanel()
            Task { @MainActor in
                try? await Task.sleep(for: PasteEngine.postHidePasteDelay)
                PasteEngine.shared.simulateCommandV()
            }
            moveItemToTopIfPreferred(item)
        }
    }

    /// Moves the item to the top when the "Move Item to Top After Pasting" preference is enabled.
    /// Applies to every use of an item: pasting, plain-text pasting, and copying.
    func moveItemToTopIfPreferred(_ item: ClipboardItem) {
        guard UserDefaults.standard.bool(forKey: "moveToTopAfterPaste") else { return }
        moveItemToTop(item)
    }

    /// Copies the current selection: merges multiple items, or copies the single focused item.
    /// Returns `false` when nothing is selected so the caller can let the event pass through.
    @discardableResult
    func copySelection() -> Bool {
        guard !selectedItemIDs.isEmpty else { return false }

        if selectedItemIDs.count > 1 {
            batchCopy()
            return true
        }

        guard let firstID = selectedItemIDs.first,
              let item = displayedItemsForInteraction.first(where: { $0.id == firstID }) else {
            return false
        }

        copyToClipboard(item: item)
        return true
    }

    func copyToClipboard(item: ClipboardItem) {
        Task { @MainActor in
            guard let record = await StorageManager.shared.loadPasteRecord(id: item.id) else { return }

            let wroteToPasteboard = await PasteEngine.shared.writeToPasteboard(
                record: record,
                preferPlainText: shouldForcePlainTextOutput
            )
            guard wroteToPasteboard else { return }
            playCopySound()
            moveItemToTopIfPreferred(item)
        }
    }

    func playCopySound() {
        settingsViewModel.playCopySound()
    }

    func pinItem(item: ClipboardItem) {
        setFavoriteState(for: item, isFavorite: !item.isPinned)
    }

    func addItemToBuiltInGroup(item: ClipboardItem, group: ClipboardBuiltInGroup) {
        switch group {
        case .favorites:
            setFavoriteState(for: item, isFavorite: true)
        }
    }

    func editItemContent(item: ClipboardItem) {
        EditWindowManager.shared.openEditor(for: item, viewModel: self)
    }

}
