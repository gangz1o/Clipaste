import AppKit
import SwiftUI

extension ClipboardViewModel {
    func recognizeTextFromImage(item: ClipboardItem) {
        guard item.contentType == .image else { return }

        Task { @MainActor in
            var imageData = await StorageManager.shared.loadImageData(id: item.id)
            if imageData == nil {
                imageData = await StorageManager.shared.loadPreviewImageData(id: item.id)
            }
            guard let imageData else {
                return
            }

            let title = item.customTitle ?? item.appName
            OCRResultWindowManager.shared.openResult(imageData: imageData, sourceTitle: title)
        }
    }

    func editImage(item: ClipboardItem) {
        guard item.contentType == .image else { return }

        Task.detached(priority: .userInitiated) {
            let imageData = await StorageManager.shared.loadImageData(id: item.id)
            let previewData = await StorageManager.shared.loadPreviewImageData(id: item.id)

            guard let sourceData = imageData ?? previewData else {
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
                return
            }

            await MainActor.run {
                ImageEditWindowManager.shared.openEditor(tempURL: tempURL, originalItem: item, viewModel: self)
            }
        }
    }

    func saveEditedImage(tempURL: URL, originalItem: ClipboardItem) {
        let manualMethod = ClipboardSourceMetadata.manualMethod

        Task.detached(priority: .utility) {
            guard let editedData = ClipboardFileReference.accessibleData(
                from: tempURL,
                maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
            ) else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            let newHash = CryptoHelper.sha256(data: editedData)
            let previewData = ImageProcessor.generateThumbnail(
                from: editedData,
                maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
            )
            let imageMetadata = ImageProcessor.metadata(for: editedData)
            guard ClipboardImageResourcePolicy.allowsStoredImage(imageMetadata) else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            let appIconDominantColorHex = await StorageManager.shared.loadAppIconDominantColorHex(id: originalItem.id)
            let appIconData = await StorageManager.shared.loadAppIconData(id: originalItem.id)

            StorageManager.shared.upsertRecord(
                hash: newHash,
                text: nil,
                appID: originalItem.sourceBundleIdentifier,
                appName: originalItem.appName,
                appIconDominantColorHex: appIconDominantColorHex,
                appIconData: appIconData,
                type: ClipboardContentType.image.rawValue,
                previewImageData: previewData,
                imageData: editedData,
                imageMetadata: imageMetadata,
                sourcePlatformRawValue: originalItem.sourcePlatformRawValue,
                sourceDeviceName: originalItem.sourceDeviceName,
                captureMethodRawValue: manualMethod,
                captureSessionID: originalItem.captureSessionID
            )

            StorageManager.shared.processOCRForImage(hash: newHash, imageData: editedData)

            try? FileManager.default.removeItem(at: tempURL)

            print("✅ [saveEditedImage] 编辑图片已作为新记录保存: \(newHash)")
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
                appIconDominantColorHex: item.appIconDominantColorHex,
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
                hasRTF: item.hasRTF,
                sourcePlatformRawValue: item.sourcePlatformRawValue,
                sourceDeviceName: item.sourceDeviceName,
                captureMethodRawValue: item.captureMethodRawValue,
                captureSessionID: item.captureSessionID
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

}
