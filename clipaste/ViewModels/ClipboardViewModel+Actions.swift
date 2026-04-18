import AppKit
import SwiftUI

extension ClipboardViewModel {
    func suppressNextPaste(for itemID: UUID) {
        suppressedPasteItemIDs.insert(itemID)
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

        withAnimation(.easeOut(duration: 0.2)) {
            removeItems(withIDs: idsToDelete)
        }

        if let qlItem = quickLookItem, idsToDelete.contains(qlItem.id) {
            dismissQuickLook()
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
        print("✅ 批量删除 \(hashesToDelete.count) 条记录，保留 \(protectedItems.count) 条收藏记录")
    }

    func pasteToActiveApp(item: ClipboardItem) {
        if suppressedPasteItemIDs.remove(item.id) != nil {
            return
        }

        print("🚀 触发双击事件: \(item.id)")

        selectedItemIDs = [item.id]
        lastSelectedID = item.id

        Task { @MainActor in
            guard let record = await StorageManager.shared.loadPasteRecord(id: item.id) else {
                print("❌ 未找到可复制的记录: \(item.id)")
                return
            }

            let wroteToPasteboard = await PasteEngine.shared.writeToPasteboard(
                record: record,
                preferPlainText: shouldForcePlainTextOutput
            )
            guard wroteToPasteboard else {
                print("❌ 写入系统剪贴板失败: \(item.id)")
                return
            }

            ClipboardPanelManager.shared.forceHidePanel()

            let autoPaste = UserDefaults.standard.object(forKey: "autoPasteToActiveApp") as? Bool ?? true
            if autoPaste {
                guard PasteEngine.shared.checkAccessibilityPermissions() else {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    PasteEngine.shared.simulateCommandV()
                }
            } else {
                print("🛑 用户关闭了自动粘贴，仅执行复制并隐藏面板")
            }

            let moveToTop = UserDefaults.standard.bool(forKey: "moveToTopAfterPaste")
            if moveToTop {
                moveItemToTop(item)
            }
        }
    }

    func pasteAsPlainText(item: ClipboardItem) {
        Task { @MainActor in
            guard let text = await StorageManager.shared.loadPlainText(id: item.id) else { return }
            PasteEngine.shared.writePlainTextToPasteboard(text: text)
            ClipboardPanelManager.shared.forceHidePanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                PasteEngine.shared.simulateCommandV()
            }
        }
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

    func editImage(item: ClipboardItem) {
        guard item.contentType == .image else { return }

        Task.detached(priority: .userInitiated) {
            let imageData = await StorageManager.shared.loadImageData(id: item.id)
            let previewData = await StorageManager.shared.loadPreviewImageData(id: item.id)

            guard let sourceData = imageData ?? previewData else {
                print("❌ [editImage] 找不到原图数据: \(item.id)")
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipaste_image_edit", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let fileExtension = ImageProcessor.preferredFileExtension(for: item.imageUTType)
            let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")

            do {
                try sourceData.write(to: tempURL, options: .atomic)
            } catch {
                print("❌ [editImage] 写入临时图片失败: \(error)")
                return
            }

            await MainActor.run {
                ImageEditWindowManager.shared.openEditor(tempURL: tempURL, originalItem: item, viewModel: self)
            }
        }
    }

    func saveEditedImage(tempURL: URL, originalItem: ClipboardItem) {
        Task.detached(priority: .userInitiated) {
            do {
                let editedData = try Data(contentsOf: tempURL)
                let newHash = CryptoHelper.sha256(data: editedData)
                let previewData = ImageProcessor.generateThumbnail(
                    from: editedData,
                    maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
                )
                let imageMetadata = ImageProcessor.metadata(for: editedData)

                StorageManager.shared.upsertRecord(
                    hash: newHash,
                    text: nil,
                    appID: originalItem.sourceBundleIdentifier,
                    appName: originalItem.appName,
                    type: ClipboardContentType.image.rawValue,
                    previewImageData: previewData,
                    imageData: editedData,
                    imageMetadata: imageMetadata
                )

                StorageManager.shared.processOCRForImage(hash: newHash, imageData: editedData)

                try? FileManager.default.removeItem(at: tempURL)

                print("✅ [saveEditedImage] 编辑图片已作为新记录保存: \(newHash)")
            } catch {
                print("❌ [saveEditedImage] 保存编辑图片失败: \(error)")
            }
        }
    }

    func saveEditedItem(_ item: ClipboardItem, newText: String) {
        if let index = itemIndexByID[item.id], items.indices.contains(index) {
            items[index] = ClipboardItem(
                id: item.id,
                contentType: item.contentType,
                contentHash: item.contentHash,
                textPreview: newText,
                searchableText: ClipboardItem.searchableTextValue(
                    plainText: newText,
                    customTitle: item.customTitle,
                    linkTitle: item.linkTitle
                ),
                sourceBundleIdentifier: item.sourceBundleIdentifier,
                appName: item.appName,
                appIcon: item.appIcon,
                appIconName: item.appIconName,
                timestamp: item.timestamp,
                rawText: newText,
                hasImagePreview: item.hasImagePreview,
                hasImageData: item.hasImageData,
                imageUTType: item.imageUTType,
                imagePixelWidth: item.imagePixelWidth,
                imagePixelHeight: item.imagePixelHeight,
                fileURL: item.fileURL,
                groupId: item.groupId,
                groupIDs: item.groupIDs,
                customTitle: item.customTitle,
                linkTitle: item.linkTitle,
                linkIconData: item.linkIconData,
                isPinned: item.isPinned,
                hasRTF: item.hasRTF
            )
            refreshDisplayedItemsFromCurrentScope()
        }

        StorageManager.shared.updateRecordText(hash: item.contentHash, newText: newText)
    }

    func renameItem(item: ClipboardItem) {
        titleEditorItem = item
    }

    func dismissTitleEditor() {
        titleEditorItem = nil
    }

    func saveCustomTitle(for item: ClipboardItem, title: String?) {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = normalizedTitle?.isEmpty == false ? normalizedTitle : nil

        updateItem(id: item.id) { updatedItem in
            updatedItem.customTitle = resolvedTitle
        }

        if titleEditorItem?.id == item.id {
            titleEditorItem = nil
        }

        StorageManager.shared.updateRecordCustomTitle(hash: item.contentHash, customTitle: resolvedTitle)
    }

    func showPreview(item: ClipboardItem) {
        if quickLookRequestedItemID == item.id || quickLookItem?.id == item.id {
            dismissQuickLook()
        } else {
            presentQuickLook(for: item)
        }
    }

    func shareItem(item: ClipboardItem) {
        sharingItem = item
    }

    func deleteItem(item: ClipboardItem) {
        guard item.isPinned == false else {
            showFavoritesDeletionBlockedNotice()
            print("🛡️ 已阻止删除收藏记录: \(item.id)")
            return
        }
        let fallbackSelectionID = selectionCandidateAfterRemoving(ids: [item.id])
        withAnimation(.easeOut(duration: 0.2)) {
            removeItems(withIDs: [item.id])
        }
        applySelectionAfterDeletion(fallbackID: fallbackSelectionID)
        if quickLookItem?.id == item.id {
            dismissQuickLook()
        }
        StorageManager.shared.deleteRecord(hash: item.contentHash)
    }
}

private extension ClipboardViewModel {
    var operationNoticeLocale: Locale {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
        return language.resolvedLocale
    }

    func showFavoritesDeletionBlockedNotice() {
        showOperationNotice(
            String(
                localized: "Items in Favorites can't be deleted. Remove them from Favorites first.",
                locale: operationNoticeLocale
            )
        )
    }

    func showFavoritesPreservedNotice(deletedCount: Int, preservedCount: Int) {
        let format = String(
            localized: "Deleted %lld items. Kept %lld item(s) in Favorites.",
            locale: operationNoticeLocale
        )
        let message = withVaList([deletedCount, preservedCount]) { pointer in
            NSString(format: format, locale: operationNoticeLocale, arguments: pointer) as String
        }
        showOperationNotice(message)
    }

    func showOperationNotice(_ message: String) {
        operationNoticeHideTask?.cancel()
        operationNotice = message

        operationNoticeHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard Task.isCancelled == false else { return }
            self?.operationNotice = nil
            self?.operationNoticeHideTask = nil
        }
    }

    var selectedItemsForBatchAction: [ClipboardItem] {
        let ids = selectedItemIDs
        guard !ids.isEmpty else { return [] }
        return displayedItemsForInteraction.filter { ids.contains($0.id) }
    }

    func batchSetFavoriteState(_ isFavorite: Bool) {
        let targetItems = selectedItemsForBatchAction
        guard !targetItems.isEmpty else { return }

        for item in targetItems {
            setFavoriteState(for: item, isFavorite: isFavorite)
        }

        clearSelection()
    }

    func setFavoriteState(for item: ClipboardItem, isFavorite: Bool) {
        guard item.isPinned != isFavorite else { return }

        updateItem(id: item.id) { updatedItem in
            updatedItem.isPinned = isFavorite
        }

        StorageManager.shared.togglePin(hash: item.contentHash, isPinned: isFavorite)
    }
}

private extension ClipboardViewModel {
    var shouldForcePlainTextOutput: Bool {
        if isPlainTextModifierHeld {
            return true
        }

        return pasteTextFormat == .plainText
    }

    func moveItemToTop(_ item: ClipboardItem) {
        if let index = itemIndexByID[item.id], index != 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                moveItem(withID: item.id, to: 0)
            }
        }
        selectedItemIDs = [item.id]
        lastSelectedID = item.id

        Task {
            await StorageManager.shared.moveItemToTop(id: item.id)
        }
    }
}
