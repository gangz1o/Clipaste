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

        // ⚠️ 智能嗅探：在录入瞬间决定数据类型，持久化入库
        let sniffedType = Self.sniffTextType(text)

        return ClipboardRecordPayload(
            hash: contentHash,
            text: text,
            appID: appID,
            appName: appName,
            type: sniffedType.rawValue
        )
    }

    /// 录入期智能嗅探引擎：判断文本的真实语义类型。
    /// 优先级：link → code → text 兜底。
    /// ⚠️ 架构红线：此方法仅在录入时执行一次，结果持久化入库，UI 层绝不做运行时判断。
    private static func sniffTextType(_ text: String) -> ClipboardContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Link 判断：合法 URL（http:// 或 https://）
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            return .link
        }

        // 2. Code 判断：复用 SyntaxHighlightService 的特征匹配
        if SyntaxHighlightService.looksLikeCode(text) {
            return .code
        }

        // 3. 兜底：纯文本
        return .text
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
            let previewData = ImageProcessor.generateThumbnail(from: data)
            let imageMetadata = ImageProcessor.metadata(for: data)

            if await StorageManager.shared.recordExists(hash: contentHash) {
                StorageManager.shared.upsertRecord(
                    hash: contentHash,
                    text: nil,
                    appID: appID,
                    appName: appName,
                    type: ClipboardContentType.image.rawValue,
                    previewImageData: previewData,
                    imageData: data,
                    imageMetadata: imageMetadata
                )
                return
            }

            StorageManager.shared.upsertRecord(
                hash: contentHash,
                text: nil,
                appID: appID,
                appName: appName,
                type: ClipboardContentType.image.rawValue,
                previewImageData: previewData,
                imageData: data,
                imageMetadata: imageMetadata
            )

            StorageManager.shared.processOCRForImage(hash: contentHash, imageData: data)
        }
    }

    private func enqueueUpsert(
        for payload: ClipboardRecordPayload,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil
    ) {
        StorageManager.shared.upsertRecord(
            hash: payload.hash,
            text: payload.text,
            appID: payload.appID,
            appName: payload.appName,
            type: payload.type,
            previewImageData: previewImageData,
            imageData: imageData,
            imageMetadata: imageMetadata
        )

        // 链接类型 → 触发 LinkPresentation 抓取，让链接变成漂亮的书签卡片
        if payload.type == ClipboardContentType.link.rawValue,
           let text = payload.text {
            StorageManager.shared.processLinkMetadata(hash: payload.hash, urlString: text.trimmingCharacters(in: .whitespacesAndNewlines))
            // 链接同样触发高亮（部分 URL 可能包含代码参数）
            StorageManager.shared.processSyntaxHighlight(hash: payload.hash, text: text)
        }

        // 代码/纯文本 → 静默触发后台语法高亮
        if (payload.type == ClipboardContentType.text.rawValue || payload.type == ClipboardContentType.code.rawValue),
           let text = payload.text {
            // 兼容旧逻辑：纯文本中如果恰好是 URL，也触发 LinkPresentation
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                StorageManager.shared.processLinkMetadata(hash: payload.hash, urlString: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            StorageManager.shared.processSyntaxHighlight(hash: payload.hash, text: text)
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
