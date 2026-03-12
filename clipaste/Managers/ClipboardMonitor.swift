import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTask: Task<Void, Never>?
    private let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private let utf8PlainTextType = NSPasteboard.PasteboardType("public.utf8-plain-text")
    var isIgnoredNextChange: Bool = false

    private init() {}

    deinit {
        monitoringTask?.cancel()
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self?.pollPasteboardIfNeeded()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func pollPasteboardIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        if isIgnoredNextChange {
            isIgnoredNextChange = false
            lastChangeCount = changeCount
            return
        }

        lastChangeCount = changeCount
        processPasteboardItems()
    }

    private func processPasteboardItems() {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return }

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let appID = sourceApplication?.bundleIdentifier
        let appName = sourceApplication?.localizedName

        for pasteboardItem in pasteboardItems {
            if let payload = makeFileURLPayload(from: pasteboardItem, appID: appID, appName: appName) {
                enqueueUpsert(for: payload)
                continue
            }

            if let imageData = imageData(from: pasteboardItem) {
                handleImagePayload(data: imageData, appID: appID, appName: appName)
                continue
            }

            guard let payload = makeTextPayload(from: pasteboardItem, appID: appID, appName: appName) else {
                continue
            }

            enqueueUpsert(for: payload)
        }
    }

    private func makeFileURLPayload(
        from pasteboardItem: NSPasteboardItem,
        appID: String?,
        appName: String?
    ) -> ClipboardRecordPayload? {
        guard let fileURLString = pasteboardItem.string(forType: fileURLType) else { return nil }

        let fileData = pasteboardItem.data(forType: fileURLType) ?? Data(fileURLString.utf8)
        let contentHash = CryptoHelper.sha256(data: fileData)

        return ClipboardRecordPayload(
            hash: contentHash,
            text: fileURLString,
            appID: appID,
            appName: appName,
            type: ClipboardContentType.fileURL.rawValue
        )
    }

    private func makeTextPayload(
        from pasteboardItem: NSPasteboardItem,
        appID: String?,
        appName: String?
    ) -> ClipboardRecordPayload? {
        guard let text = pasteboardItem.string(forType: utf8PlainTextType) ?? pasteboardItem.string(forType: .string) else {
            return nil
        }

        let textData = pasteboardItem.data(forType: utf8PlainTextType) ?? Data(text.utf8)
        let contentHash = CryptoHelper.sha256(data: textData)

        return ClipboardRecordPayload(
            hash: contentHash,
            text: text,
            appID: appID,
            appName: appName,
            type: ClipboardContentType.text.rawValue
        )
    }

    private func imageData(from pasteboardItem: NSPasteboardItem) -> Data? {
        if let pngData = pasteboardItem.data(forType: .png) {
            return pngData
        }

        if let tiffData = pasteboardItem.data(forType: .tiff) {
            return tiffData
        }

        return nil
    }

    private func handleImagePayload(data: Data, appID: String?, appName: String?) {
        Task.detached(priority: .userInitiated) {
            let contentHash = CryptoHelper.sha256(data: data)

            if await StorageManager.shared.recordExists(hash: contentHash) {
                StorageManager.shared.upsertRecord(
                    hash: contentHash,
                    text: nil,
                    appID: appID,
                    appName: appName,
                    type: ClipboardContentType.image.rawValue,
                    thumbnailPath: nil,
                    originalFilePath: nil
                )
                return
            }

            guard let savedPaths = try? await LocalFileManager.shared.saveImagePayload(data: data, hash: contentHash) else {
                return
            }

            StorageManager.shared.upsertRecord(
                hash: contentHash,
                text: nil,
                appID: appID,
                appName: appName,
                type: ClipboardContentType.image.rawValue,
                thumbnailPath: savedPaths.thumbnailPath,
                originalFilePath: savedPaths.originalPath
            )

            // 静默触发后台 OCR，将图片中的文字写入 plainText 以支持全局搜索。
            // 使用 originalPath（完整原始图片）以获得最高 OCR 识别率。
            if let absolutePath = LocalFileManager.shared.url(forRelativePath: savedPaths.originalPath)?.path {
                StorageManager.shared.processOCRForImage(hash: contentHash, absoluteImagePath: absolutePath)
            }
        }
    }

    private func enqueueUpsert(
        for payload: ClipboardRecordPayload,
        thumbnailPath: String? = nil,
        originalFilePath: String? = nil
    ) {
        StorageManager.shared.upsertRecord(
            hash: payload.hash,
            text: payload.text,
            appID: payload.appID,
            appName: payload.appName,
            type: payload.type,
            thumbnailPath: thumbnailPath,
            originalFilePath: originalFilePath
        )

        // 如果存入的是一段纯文本 URL，悄悄触发 LinkPresentation 抓取，让链接变成漂亮的书签卡片
        if payload.type == ClipboardContentType.text.rawValue,
           let text = payload.text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                StorageManager.shared.processLinkMetadata(hash: payload.hash, urlString: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}

private struct ClipboardRecordPayload {
    let hash: String
    let text: String?
    let appID: String?
    let appName: String?
    let type: String
}

extension Notification.Name {
    nonisolated static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
}
