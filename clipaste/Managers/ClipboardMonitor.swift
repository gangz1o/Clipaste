import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private let defaults: UserDefaults
    private var lastChangeCount: Int = 0
    private var monitoringTask: Task<Void, Never>?
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private let utf8PlainTextType = NSPasteboard.PasteboardType("public.utf8-plain-text")
    private var isMonitoringLifecycleActive = false
    private var isMonitoringPaused = false
    private var pollingInterval: TimeInterval
    private var ignoredBundleIdentifiers: Set<String>
    var isIgnoredNextChange: Bool = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isMonitoringPaused = defaults.bool(forKey: Keys.isMonitoringPaused)
        self.pollingInterval = Self.sanitizedPollingInterval(
            defaults.object(forKey: Keys.monitorInterval) as? Double
        )
        self.ignoredBundleIdentifiers = IgnoredAppsService.ignoredBundleIdentifierSet(defaults: defaults)
        observePreferences()
    }

    deinit {
        monitoringTask?.cancel()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func startMonitoring() {
        isMonitoringLifecycleActive = true
        refreshMonitoringLoop(resetChangeBaseline: true)
    }

    func stopMonitoring() {
        isMonitoringLifecycleActive = false
        cancelMonitoringLoop()
    }

    private func observePreferences() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyPersistedPreferences()
            }
        }
    }

    private func applyPersistedPreferences() {
        let persistedPauseState = defaults.bool(forKey: Keys.isMonitoringPaused)
        let persistedInterval = Self.sanitizedPollingInterval(
            defaults.object(forKey: Keys.monitorInterval) as? Double
        )
        let persistedIgnoredBundleIdentifiers = IgnoredAppsService.ignoredBundleIdentifierSet(defaults: defaults)

        let pauseStateChanged = persistedPauseState != isMonitoringPaused
        let intervalChanged = persistedInterval != pollingInterval
        let ignoredAppsChanged = persistedIgnoredBundleIdentifiers != ignoredBundleIdentifiers

        guard pauseStateChanged || intervalChanged || ignoredAppsChanged else { return }

        isMonitoringPaused = persistedPauseState
        pollingInterval = persistedInterval
        ignoredBundleIdentifiers = persistedIgnoredBundleIdentifiers

        // Resume 时需要丢弃暂停期间的剪贴板变化，避免把“暂停期间产生的最新剪贴板”补录进历史。
        let shouldResetBaseline = pauseStateChanged && persistedPauseState == false
        refreshMonitoringLoop(resetChangeBaseline: shouldResetBaseline)
    }

    private func refreshMonitoringLoop(resetChangeBaseline: Bool) {
        if resetChangeBaseline {
            lastChangeCount = pasteboard.changeCount
            isIgnoredNextChange = false
        }

        let shouldMonitor = isMonitoringLifecycleActive && !isMonitoringPaused
        guard shouldMonitor else {
            cancelMonitoringLoop()
            return
        }

        let intervalNanoseconds = Self.nanoseconds(for: pollingInterval)
        cancelMonitoringLoop()

        monitoringTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                await self?.pollPasteboardIfNeeded()
            }
        }
    }

    private func cancelMonitoringLoop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private static func sanitizedPollingInterval(_ rawValue: Double?) -> TimeInterval {
        let candidate = rawValue ?? DefaultValues.monitorInterval
        guard candidate.isFinite, candidate >= 0.1 else {
            return DefaultValues.monitorInterval
        }

        return candidate
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((interval * 1_000_000_000).rounded())
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
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let appID = sourceApplication?.bundleIdentifier
        let appName = sourceApplication?.localizedName
        let sourceAppIconData = sourceApplication?.icon?.tiffRepresentation

        if let appID, ignoredBundleIdentifiers.contains(appID) {
            return
        }

        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return }
        var recordPayloads: [ClipboardRecordPayload] = []
        var imagePayloads: [ClipboardImagePayload] = []

        for pasteboardItem in pasteboardItems {
            let textPayload = makeTextPayload(from: pasteboardItem, appID: appID, appName: appName)

            if let imageData = imageData(from: pasteboardItem) {
                if let textPayload, shouldPreferTextPayload(textPayload, overImageFrom: pasteboardItem) {
                    recordPayloads.append(textPayload)
                } else {
                    imagePayloads.append(ClipboardImagePayload(data: imageData, appID: appID, appName: appName))
                }
                continue
            }

            if let imageData = imageDataFromFileURL(from: pasteboardItem) {
                imagePayloads.append(ClipboardImagePayload(data: imageData, appID: appID, appName: appName))
                continue
            }

            if let payload = makeFileURLPayload(from: pasteboardItem, appID: appID, appName: appName) {
                recordPayloads.append(payload)
                continue
            }

            if let payload = textPayload {
                recordPayloads.append(payload)
            }
        }

        guard imagePayloads.isEmpty == false || recordPayloads.isEmpty == false else {
            return
        }

        Task.detached(priority: .userInitiated) {
            await Self.persistCapturedPayloads(
                recordPayloads: recordPayloads,
                imagePayloads: imagePayloads,
                sourceAppIconData: sourceAppIconData
            )
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
            type: ClipboardContentType.fileURL.rawValue,
            rtfData: nil,
            richTextArchive: nil
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
        let richTextArchive = ClipboardRichTextArchive.fromPasteboardItem(pasteboardItem)
        let rtfData = richTextArchive?.previewRTFData

        // Excel/WPS 这类结构化表格复制通常带有 HTML/Tabular Text，
        // 这里强制归为普通文本，避免被代码分类器误判为 code。
        let sniffedType: ClipboardContentType
        if richTextArchive?.hasComplexPreviewRepresentations == true {
            sniffedType = .text
        } else {
            // ⚠️ 智能嗅探：在录入瞬间决定数据类型，持久化入库
            sniffedType = Self.sniffTextType(text)
        }

        return ClipboardRecordPayload(
            hash: contentHash,
            text: text,
            appID: appID,
            appName: appName,
            type: sniffedType.rawValue,
            rtfData: rtfData,
            richTextArchive: richTextArchive
        )
    }

    /// 录入期智能嗅探引擎：判断文本的真实语义类型。
    /// 优先级：link → code → text 兜底。
    /// ⚠️ 架构红线：此方法仅在录入时执行一次，结果持久化入库，UI 层绝不做运行时判断。
    private static func sniffTextType(_ text: String) -> ClipboardContentType {
        ClipboardContentClassifier.classify(text)
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

    private func imageDataFromFileURL(from pasteboardItem: NSPasteboardItem) -> Data? {
        guard let fileURLString = pasteboardItem.string(forType: fileURLType) else { return nil }
        return ClipboardFileReference.loadImageData(from: fileURLString)
    }

    private func shouldPreferTextPayload(
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

    private nonisolated static func persistCapturedPayloads(
        recordPayloads: [ClipboardRecordPayload],
        imagePayloads: [ClipboardImagePayload],
        sourceAppIconData: Data?
    ) async {
        let appIconDominantColorHex = sourceAppIconData.flatMap(Self.extractDominantColorHex(from:))

        for imagePayload in imagePayloads {
            await persistImagePayload(
                imagePayload,
                appIconDominantColorHex: appIconDominantColorHex
            )
        }

        for recordPayload in recordPayloads {
            persistRecordPayload(
                recordPayload,
                appIconDominantColorHex: appIconDominantColorHex
            )
        }
    }

    private nonisolated static func persistImagePayload(
        _ payload: ClipboardImagePayload,
        appIconDominantColorHex: String?
    ) async {
        let contentHash = CryptoHelper.sha256(data: payload.data)
        let previewData = ImageProcessor.generateThumbnail(
            from: payload.data,
            maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
        )
        let imageMetadata = ImageProcessor.metadata(for: payload.data)
        let recordExists = await StorageManager.shared.recordExists(hash: contentHash)

        StorageManager.shared.upsertRecord(
            hash: contentHash,
            text: nil,
            appID: payload.appID,
            appName: payload.appName,
            appIconDominantColorHex: appIconDominantColorHex,
            type: ClipboardContentType.image.rawValue,
            previewImageData: previewData,
            imageData: payload.data,
            imageMetadata: imageMetadata
        )

        guard recordExists == false else {
            return
        }

        StorageManager.shared.processOCRForImage(hash: contentHash, imageData: payload.data)
    }

    private nonisolated static func persistRecordPayload(
        _ payload: ClipboardRecordPayload,
        appIconDominantColorHex: String?
    ) {
        StorageManager.shared.upsertRecord(
            hash: payload.hash,
            text: payload.text,
            appID: payload.appID,
            appName: payload.appName,
            appIconDominantColorHex: appIconDominantColorHex,
            type: payload.type,
            rtfData: payload.rtfData,
            richTextArchiveData: payload.richTextArchive?.encodedData()
        )

        // 链接类型 → 触发 LinkPresentation 抓取，让链接变成漂亮的书签卡片
        if payload.type == ClipboardContentType.link.rawValue,
           let text = payload.text {
            StorageManager.shared.processLinkMetadata(
                hash: payload.hash,
                urlString: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if payload.richTextArchive == nil, payload.rtfData == nil {
                StorageManager.shared.processSyntaxHighlight(hash: payload.hash, text: text)
            }
        }

        // 代码/纯文本 → 静默触发后台语法高亮
        if (payload.type == ClipboardContentType.text.rawValue || payload.type == ClipboardContentType.code.rawValue),
           payload.richTextArchive == nil,
           payload.rtfData == nil,
           let text = payload.text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                StorageManager.shared.processLinkMetadata(
                    hash: payload.hash,
                    urlString: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            StorageManager.shared.processSyntaxHighlight(hash: payload.hash, text: text)
        }
    }

    private nonisolated static func extractDominantColorHex(from iconData: Data) -> String? {
        autoreleasepool {
            guard let image = NSImage(data: iconData) else {
                return nil
            }

            return image.dominantColorHex()
        }
    }
}

private extension ClipboardMonitor {
    enum Keys {
        static let isMonitoringPaused = "isMonitoringPaused"
        static let monitorInterval = "monitorInterval"
    }

    enum DefaultValues {
        static let monitorInterval: TimeInterval = 0.5
    }
}

private struct ClipboardRecordPayload: Sendable {
    let hash: String
    let text: String?
    let appID: String?
    let appName: String?
    let type: String
    let rtfData: Data?
    let richTextArchive: ClipboardRichTextArchive?
}

private struct ClipboardImagePayload: Sendable {
    let data: Data
    let appID: String?
    let appName: String?

    init(data: Data, appID: String? = nil, appName: String? = nil) {
        self.data = data
        self.appID = appID
        self.appName = appName
    }
}

extension Notification.Name {
    nonisolated static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
    nonisolated static let didFinishDataMigration = Notification.Name("com.clipaste.didFinishDataMigration")
}
