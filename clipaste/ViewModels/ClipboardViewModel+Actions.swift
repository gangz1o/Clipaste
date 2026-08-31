import AppKit
import SwiftUI

extension ClipboardViewModel {
    func suppressNextPaste(for itemID: UUID) {
        suppressedPasteItemIDs.insert(itemID)

        // The ancestor tap gesture consumes this synchronously during the same
        // input event. Expire an unconsumed marker so a keyboard, accessibility,
        // or non-single-click action cannot suppress a later intentional paste.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.suppressedPasteItemIDs.remove(itemID)
        }
    }

    func batchCopy() {
        let ids = selectedItemIDs
        guard !ids.isEmpty else { return }

        let orderedItems = displayedItemsForInteraction.filter { ids.contains($0.id) }

        Task(priority: .userInitiated) { @MainActor in
            var fullTexts: [String] = []
            fullTexts.reserveCapacity(orderedItems.count)

            for item in orderedItems {
                let plainText = await StorageManager.shared.loadPlainText(id: item.id)
                let resolvedText = plainText ?? item.rawText ?? item.textPreview
                guard resolvedText.isEmpty == false else { continue }
                fullTexts.append(resolvedText)
            }

            let merged = fullTexts.joined(separator: "\n\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(merged, forType: .string)
            playCopySound()

            print("✅ 批量复制 \(orderedItems.count) 条记录到剪贴板")
            clearSelection()
        }
    }

    func batchAssignToGroup(groupId: String?) {
        let ids = selectedItemIDs
        guard !ids.isEmpty else { return }

        let targetItems = displayedItemsForInteraction.filter { ids.contains($0.id) }

        if let groupId {
            for item in targetItems {
                updateItem(id: item.id) { updatedItem in
                    if updatedItem.groupIDs.contains(groupId) == false {
                        updatedItem.groupIDs.append(groupId)
                    }
                }
                StorageManager.shared.assignToGroup(hash: item.contentHash, groupId: groupId)
            }
        } else {
            for item in targetItems {
                updateItem(id: item.id) { updatedItem in
                    updatedItem.groupIDs.removeAll()
                }
                StorageManager.shared.removeRecordFromAllGroups(hash: item.contentHash)
            }
        }

        clearSelection()
    }

    func addSelectionToFavorites() {
        batchSetFavoriteState(true)
    }

    func removeSelectionFromFavorites() {
        batchSetFavoriteState(false)
    }

    func toggleFavoriteForSelection() {
        let targetItems = selectedItemsForBatchAction
        guard !targetItems.isEmpty else { return }

        let shouldFavorite = targetItems.contains(where: { $0.isPinned == false })
        batchSetFavoriteState(shouldFavorite)
    }

    /// Deletes the current selection, respecting the `requireCmdToDelete` setting.
    ///
    /// - Parameter isCommandHeld: Pass `true` when the user triggered deletion with ⌘+Backspace.
    ///   When `false`, deletion is only performed if `requireCmdToDelete` is disabled.
    func deleteSelection(isCommandHeld: Bool = false) {
        if settingsViewModel.requireCmdToDelete, !isCommandHeld {
            return
        }
        guard !selectedItemIDs.isEmpty else { return }
        batchDelete()
    }

    func batchDelete() {
        let ids = selectedItemIDs
        guard !ids.isEmpty else { return }

        let targetItems = displayedItemsForInteraction.filter { ids.contains($0.id) }
        let protectedItems = targetItems.filter(\.isPinned)
        let deletableItems = targetItems.filter { $0.isPinned == false }
        guard !deletableItems.isEmpty else {
            selectedItemIDs = Set(protectedItems.map(\.id))
            lastSelectedID = protectedItems.first?.id
            showFavoritesDeletionBlockedNotice()
            print("🛡️ 已跳过 \(protectedItems.count) 条收藏记录，未执行删除")
            return
        }

        let idsToDelete = Set(deletableItems.map(\.id))
        let protectedIDs = Set(protectedItems.map(\.id))
        let hashesToDelete = deletableItems.map(\.contentHash)
        let fallbackSelectionID = selectionCandidateAfterRemoving(ids: idsToDelete)

        // Dismiss the QuickLook popover BEFORE removing the anchor card.
        // The popover is attached to each ClipboardCardView, so tearing the
        // card down while it's still presenting can leave NSPopover with a
        // dangling parent view and crash on rapid repeated deletes.
        if let qlItem = quickLookItem, idsToDelete.contains(qlItem.id) {
            dismissQuickLook()
        }
        dismissAutoPreviewIfNeeded()

        withAnimation(.easeOut(duration: 0.2)) {
            removeItems(withIDs: idsToDelete)
        }

        for hash in hashesToDelete {
            StorageManager.shared.deleteRecord(hash: hash)
        }

        if protectedIDs.isEmpty == false {
            showFavoritesPreservedNotice(deletedCount: hashesToDelete.count, preservedCount: protectedItems.count)
        }

        applySelectionAfterDeletion(
            fallbackID: fallbackSelectionID,
            preservedSelectionIDs: protectedIDs
        )
    }
}
