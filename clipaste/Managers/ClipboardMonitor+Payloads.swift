import AppKit
import Foundation
import os

@MainActor
extension ClipboardMonitor {
    static func sniffTextType(_ text: String) -> ClipboardContentType {
        ClipboardContentClassifier.classify(text)
    }

    func imageData(from pasteboardItem: NSPasteboardItem) -> Data? {
        if let pngData = pasteboardItem.data(forType: .png) {
            let metadata = ImageProcessor.metadata(for: pngData)
            return ClipboardImageResourcePolicy.allowsStoredImage(metadata) ? pngData : nil
        }

        if let tiffData = pasteboardItem.data(forType: .tiff) {
            let metadata = ImageProcessor.metadata(for: tiffData)
            return ClipboardImageResourcePolicy.allowsStoredImage(metadata) ? tiffData : nil
        }

        return nil
    }

    func imageFileURL(from pasteboardItem: NSPasteboardItem) -> URL? {
        guard let fileURLString = pasteboardItem.string(forType: fileURLType) else { return nil }
        guard let fileURL = ClipboardFileReference.resolvedURL(from: fileURLString),
              ClipboardFileReference.isLikelyImageFileURL(fileURL) else {
            return nil
        }
        return fileURL
    }

    func shouldPreferTextPayload(
        _ payload: ClipboardRecordPayload,
        overImageFrom pasteboardItem: NSPasteboardItem
    ) -> Bool {
        guard let text = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return false
        }

        if payload.richTextArchive?.isEmpty == false {
            return true
        }

        if text.contains("\t") || text.contains("\n") {
            return true
        }

        if text.count >= 80 {
            return true
        }

        if ClipboardContentClassifier.isLikelyLink(text) {
            return false
        }

        let textualTypeIdentifiers = Set(
            pasteboardItem.types.map(\.rawValue).filter {
                $0.contains("text") || $0.contains("html") || $0.contains("rtf")
            }
        )

        return textualTypeIdentifiers.isEmpty == false
    }

    nonisolated static func persistCapturedPayloads(
        storage: StorageManager,
        recordPayloads: [ClipboardRecordPayload],
        imagePayloads: [ClipboardImagePayload],
        sourceAppIconData: Data?,
        shouldFetchLinkMetadata: Bool
    ) async {
        let appIconDominantColorHex = sourceAppIconData.flatMap(Self.extractDominantColorHex(from:))

        for imagePayload in imagePayloads {
            await persistImagePayload(
                imagePayload,
                storage: storage,
                appIconDominantColorHex: appIconDominantColorHex,
                appIconData: sourceAppIconData
            )
        }

        for recordPayload in recordPayloads {
            await persistRecordPayload(
                recordPayload,
                storage: storage,
                appIconDominantColorHex: appIconDominantColorHex,
                appIconData: sourceAppIconData,
                shouldFetchLinkMetadata: shouldFetchLinkMetadata
            )
        }
    }

    nonisolated static func persistImagePayload(
        _ payload: ClipboardImagePayload,
        storage: StorageManager,
        appIconDominantColorHex: String?,
        appIconData: Data?
    ) async {
        let imageData: Data?
        switch payload.source {
        case let .data(data):
            imageData = data
        case let .fileURL(fileURL):
            imageData = ClipboardFileReference.loadImageData(from: fileURL)
        }

        guard let imageData else {
            Self.resourceLogger.notice("Skipped an image payload that could not be read within the configured resource budget")
            if let fallbackRecordPayload = payload.fallbackRecordPayload {
                await persistRecordPayload(
                    fallbackRecordPayload,
                    storage: storage,
                    appIconDominantColorHex: appIconDominantColorHex,
                    appIconData: appIconData,
                    shouldFetchLinkMetadata: false
                )
            }
            return
        }

        let imageMetadata = ImageProcessor.metadata(for: imageData)
        guard ClipboardImageResourcePolicy.allowsStoredImage(imageMetadata) else {
            Self.resourceLogger.notice("Skipped an image payload that exceeded the configured resource budget")
            return
        }

        let contentHash = CryptoHelper.sha256(data: imageData)
        let previewData = ImageProcessor.generateThumbnail(
            from: imageData,
            maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
        )
        let recordExists = await storage.recordExists(hash: contentHash)
        // 已存在的 hash 走"置顶"路径，不再重复写入相同的 PNG 图标数据 —— 这块
        // 走 externalStorage，每次写都要重新落盘，对长时间运行的菜单栏应用是
        // 显著的累计 IO。
        let iconDataToPersist: Data? = recordExists ? nil : appIconData

        await storage.upsertRecordAndWait(
            hash: contentHash,
            text: nil,
            appID: payload.appID,
            appName: payload.appName,
            appIconDominantColorHex: appIconDominantColorHex,
            appIconData: iconDataToPersist,
            type: ClipboardContentType.image.rawValue,
            previewImageData: previewData,
            imageData: imageData,
            imageMetadata: imageMetadata,
            sourcePlatformRawValue: payload.sourcePlatformRawValue,
            sourceDeviceName: payload.sourceDeviceName,
            captureMethodRawValue: payload.captureMethodRawValue,
            captureSessionID: payload.captureSessionID
        )

        guard recordExists == false else {
            return
        }

        storage.processOCRForImage(hash: contentHash, imageData: imageData)
    }

    nonisolated static func persistRecordPayload(
        _ payload: ClipboardRecordPayload,
        storage: StorageManager,
        appIconDominantColorHex: String?,
        appIconData: Data?,
        shouldFetchLinkMetadata: Bool
    ) async {
        // 同样走"已存在则跳过 icon 写入"。文本路径之前不查 recordExists，所以
        // 每次复制都把同一份 App icon PNG 重新落盘一次。
        let recordExists = await storage.recordExists(hash: payload.hash)
        let iconDataToPersist: Data? = recordExists ? nil : appIconData

        await storage.upsertRecordAndWait(
            hash: payload.hash,
            text: payload.text,
            appID: payload.appID,
            appName: payload.appName,
            appIconDominantColorHex: appIconDominantColorHex,
            appIconData: iconDataToPersist,
            type: payload.type,
            rtfData: payload.rtfData,
            richTextArchiveData: payload.richTextArchive?.encodedData(),
            sourcePlatformRawValue: payload.sourcePlatformRawValue,
            sourceDeviceName: payload.sourceDeviceName,
            captureMethodRawValue: payload.captureMethodRawValue,
            captureSessionID: payload.captureSessionID
        )

        // 链接类型 → 触发 LinkPresentation 抓取，让链接变成漂亮的书签卡片
        if payload.type == ClipboardContentType.link.rawValue,
           let text = payload.text {
            if shouldFetchLinkMetadata {
                storage.processLinkMetadata(
                    hash: payload.hash,
                    urlString: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            if payload.richTextArchive == nil, payload.rtfData == nil {
                storage.processSyntaxHighlight(hash: payload.hash, text: text)
            }
        }

        // 代码/纯文本 → 静默触发后台语法高亮
        if (payload.type == ClipboardContentType.text.rawValue || payload.type == ClipboardContentType.code.rawValue),
           payload.richTextArchive == nil,
           payload.rtfData == nil,
           let text = payload.text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if shouldFetchLinkMetadata,
               trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                storage.processLinkMetadata(
                    hash: payload.hash,
                    urlString: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            storage.processSyntaxHighlight(hash: payload.hash, text: text)
        }
    }

    nonisolated static func extractDominantColorHex(from iconData: Data) -> String? {
        autoreleasepool {
            guard let image = NSImage(data: iconData) else {
                return nil
            }

            return image.dominantColorHex()
        }
    }
}
