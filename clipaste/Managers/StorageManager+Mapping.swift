import Foundation
import SwiftData

extension StorageManager {
    nonisolated static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        let type = ClipboardContentType(rawValue: record.typeRawValue) ?? .text

        return ClipboardItem(
            id: record.id,
            contentType: type,
            contentHash: record.contentHash,
            textPreview: makeTextPreview(plainText: record.plainText, type: type),
            searchableText: ClipboardItem.searchableTextValue(
                plainText: record.plainText,
                customTitle: record.customTitle,
                linkTitle: record.linkTitle
            ),
            sourceBundleIdentifier: record.bundleIdentifier,
            appName: record.appName,
            appIcon: nil,
            appIconName: ClipboardItem.appIconName(for: record.bundleIdentifier),
            appIconDominantColorHex: record.appIconDominantColorHex,
            timestamp: record.timestamp,
            rawText: (type == .text || type == .link || type == .code) ? record.plainText : nil,
            hasImagePreview: record.hasPreviewImage,
            hasImageData: record.hasImageData,
            imageUTType: record.imageUTType,
            imagePixelWidth: record.imagePixelWidth,
            imagePixelHeight: record.imagePixelHeight,
            fileURL: type == .fileURL ? record.plainText : nil,
            groupId: record.groupId,
            groupIDs: normalizedGroupIDs(primaryGroupID: record.groupId, groupIdsRaw: record.groupIdsRaw),
            customTitle: record.customTitle,
            linkTitle: record.linkTitle,
            linkIconData: record.linkIconData,
            isPinned: record.isPinned,
            hasRTF: record.hasRTF,
            sourcePlatformRawValue: record.sourcePlatformRawValue,
            sourceDeviceName: record.sourceDeviceName,
            captureMethodRawValue: record.captureMethodRawValue,
            captureSessionID: record.captureSessionID
        )
    }

    fileprivate nonisolated static func makeTextPreview(plainText: String?, type: ClipboardContentType) -> String {
        switch type {
        case .text, .link, .code:
            return plainText ?? ""
        case .fileURL:
            guard
                let plainText,
                let url = URL(string: plainText),
                url.isFileURL,
                !url.lastPathComponent.isEmpty
            else {
                return plainText ?? "File"
            }

            return url.lastPathComponent
        case .image:
            return "Image"
        case .color:
            return plainText ?? "Color"
        }
    }
}
