import Foundation
import SwiftData

private struct ClipboardRecordSnapshot: Sendable {
    let id: UUID
    let contentHash: String
    let bundleIdentifier: String?
    let appName: String
    let timestamp: Date
    let plainText: String?
    let hasPreviewImage: Bool
    let hasImageData: Bool
    let imageUTType: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let typeRawValue: String
    let groupId: String?
    let groupIdsRaw: String?
    let customTitle: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let hasRTF: Bool
}

struct ClipboardPasteRecord: Sendable {
    let id: UUID
    let typeRawValue: String
    let plainText: String?
    let rtfData: Data?
    let richTextArchiveData: Data?
}

nonisolated private func normalizedGroupIDs(primaryGroupID: String?, groupIdsRaw: String?) -> [String] {
    var result: [String] = []

    if let primaryGroupID, !primaryGroupID.isEmpty {
        result.append(primaryGroupID)
    }

    if let groupIdsRaw,
       let data = groupIdsRaw.data(using: .utf8),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
        for id in decoded where !id.isEmpty && result.contains(id) == false {
            result.append(id)
        }
    }

    return result
}

nonisolated private func encodedGroupIDs(_ groupIDs: [String]) -> String? {
    let cleaned = groupIDs.reduce(into: [String]()) { result, id in
        guard !id.isEmpty, result.contains(id) == false else { return }
        result.append(id)
    }

    guard !cleaned.isEmpty,
          let data = try? JSONEncoder().encode(cleaned),
          let raw = String(data: data, encoding: .utf8) else {
        return nil
    }

    return raw
}

@ModelActor
actor ClipboardSearcher {
    func searchAndMap(searchText: String, fetchLimit: Int? = nil, offset: Int = 0) async -> [ClipboardItem] {
        let query = searchText
        var descriptor: FetchDescriptor<ClipboardRecord>

        if query.isEmpty {
            descriptor = FetchDescriptor<ClipboardRecord>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            let predicate = #Predicate<ClipboardRecord> { record in
                (record.plainText?.localizedStandardContains(query) == true) ||
                (record.appLocalizedName?.localizedStandardContains(query) == true)
            }

            descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        if let fetchLimit, fetchLimit > 0 {
            descriptor.fetchLimit = fetchLimit
        }

        if offset > 0 {
            descriptor.fetchOffset = offset
        }

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = records.map { record in
            let truncatedText: String? = {
                guard let text = record.plainText else { return nil }
                return text.count > 500 ? String(text.prefix(500)) : text
            }()

            return ClipboardRecordSnapshot(
                id: record.id,
                contentHash: record.contentHash,
                bundleIdentifier: record.appBundleID,
                appName: record.appLocalizedName ?? "Unknown App",
                timestamp: record.timestamp,
                plainText: truncatedText,
                hasPreviewImage: record.previewImageData != nil,
                hasImageData: record.imageData != nil,
                imageUTType: record.imageUTType,
                imagePixelWidth: record.imagePixelWidth,
                imagePixelHeight: record.imagePixelHeight,
                typeRawValue: record.typeRawValue,
                groupId: record.groupId,
                groupIdsRaw: record.groupIdsRaw,
                customTitle: record.customTitle,
                linkTitle: record.linkTitle,
                linkIconData: record.linkIconData,
                isPinned: record.isPinned,
                hasRTF: record.rtfData != nil
            )
        }

        return snapshots.map { StorageManager.makeClipboardItem(from: $0) }
    }
}

final class StorageManager {
    nonisolated static var shared: StorageManager {
        ClipboardStorageRegistry.storage()
    }

    nonisolated let container: ModelContainer
    private let storeActor: ClipboardStoreActor
    private let cleanupActor: ClipboardStoreActor
    nonisolated private let taskLock = NSLock()
    nonisolated(unsafe) private var activeTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) private var isShuttingDown = false

    init(modelContainer: ModelContainer) {
        self.container = modelContainer
        self.storeActor = ClipboardStoreActor(modelContainer: modelContainer)
        self.cleanupActor = ClipboardStoreActor(modelContainer: modelContainer)
    }

    // Keep interactive reads off the shared write actor to avoid QoS inversions.
    private func makeReadActor() -> ClipboardStoreActor {
        ClipboardStoreActor(modelContainer: container)
    }

    /// 所有 UI / MainActor 可达的 async 读操作统一经过这里:
    /// 用 `Task.detached(priority: .userInitiated)` 把对 SwiftData `@ModelActor`
    /// (其底层执行器运行在 Background QoS 的私有队列上) 的等待动作
    /// 搬离 user-interactive 主线程,彻底消除
    /// "User-interactive thread waiting on Background QoS" 这类 Hang Risk 告警。
    /// 调用方只需像普通 async 函数一样 `await` 即可,不用手写 detached。
    nonisolated
    private func detachedRead<T: Sendable>(
        _ operation: @Sendable @escaping () async -> T
    ) async -> T {
        await Task.detached(priority: .userInitiated) {
            await operation()
        }.value
    }

    nonisolated
    func fetchItemsInBackground(
        searchText: String,
        container: ModelContainer,
        fetchLimit: Int? = nil,
        offset: Int = 0
    ) async -> [ClipboardItem] {
        await detachedRead {
            let searcher = ClipboardSearcher(modelContainer: container)
            return await searcher.searchAndMap(searchText: searchText, fetchLimit: fetchLimit, offset: offset)
        }
    }

    nonisolated
    func fetchItemsPage(
        searchText: String,
        fetchLimit: Int,
        offset: Int = 0
    ) async -> [ClipboardItem] {
        let container = self.container
        return await detachedRead {
            let searcher = ClipboardSearcher(modelContainer: container)
            return await searcher.searchAndMap(searchText: searchText, fetchLimit: fetchLimit, offset: offset)
        }
    }

    nonisolated
    func shutdown() async {
        let runningTasks = prepareForShutdown()

        for task in runningTasks {
            task.cancel()
        }

        for task in runningTasks {
            _ = await task.result
        }
    }

    func recordExists(hash: String) async -> Bool {
        let actor = storeActor
        return await detachedRead {
            await actor.recordExists(hash: hash)
        }
    }

    nonisolated
    func upsertRecord(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        appIconDominantColorHex: String? = nil,
        type: String,
        rtfData: Data? = nil,
        richTextArchiveData: Data? = nil,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil
    ) {
        let actor = self.storeActor

        spawnTrackedTask(priority: .userInitiated) {
            await actor.upsert(
                hash: hash,
                text: text,
                appID: appID,
                appName: appName,
                appIconDominantColorHex: appIconDominantColorHex,
                type: type,
                rtfData: rtfData,
                richTextArchiveData: richTextArchiveData,
                previewImageData: previewImageData,
                imageData: imageData,
                imageMetadata: imageMetadata
            )
        }
    }

    nonisolated
    func performAutoCleanup(before expirationDate: Date) {
        let actor = self.cleanupActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.cleanUpExpiredRecords(before: expirationDate)
        }
    }

    nonisolated
    func deleteRecord(hash: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.delete(hash: hash)
        }
    }

    nonisolated
    func togglePin(hash: String, isPinned: Bool) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updatePinStatus(hash: hash, isPinned: isPinned)
        }
    }

    nonisolated
    func processOCRForImage(hash: String, imageData: Data) {
        spawnTrackedTask(priority: .background) {
            guard let text = await OCREngine.extractText(from: imageData) else { return }
            guard Task.isCancelled == false else { return }
            let container = self.container
            let ocrActor = ClipboardStoreActor(modelContainer: container)
            await ocrActor.updateRecordWithOCRText(hash: hash, text: text)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.enrichment.rawValue
                    ]
                )
            }
        }
    }

    nonisolated
    func processLinkMetadata(hash: String, urlString: String) {
        spawnTrackedTask(priority: .background) {
            let (title, iconData) = await LinkMetadataEngine.fetchMetadata(for: urlString)
            guard title != nil || iconData != nil else { return }
            guard Task.isCancelled == false else { return }

            let container = self.container
            let linkActor = ClipboardStoreActor(modelContainer: container)
            await linkActor.updateRecordWithLinkMetadata(hash: hash, title: title, iconData: iconData)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.enrichment.rawValue
                    ]
                )
            }
        }
    }

    nonisolated
    func processSyntaxHighlight(hash: String, text: String) {
        spawnTrackedTask(priority: .background) {
            guard let rtfData = await SyntaxHighlightService.shared.processAndHighlight(text: text) else { return }
            guard Task.isCancelled == false else { return }
            let container = self.container
            let highlightActor = ClipboardStoreActor(modelContainer: container)
            await highlightActor.updateRecordWithRTFData(hash: hash, rtfData: rtfData)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.enrichment.rawValue
                    ]
                )
            }
        }
    }

    nonisolated
    func clearUnpinnedHistory() {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.deleteUnpinnedRecords()
        }
    }

    nonisolated
    func createGroup(name: String, systemIconName: String? = nil) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.createGroup(name: name, systemIconName: systemIconName)
        }
    }

    nonisolated
    func assignToGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.assignRecordToGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.removeRecordFromGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromAllGroups(hash: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.removeRecordFromAllGroups(recordHash: hash)
        }
    }

    nonisolated
    func renameGroup(id: String, newName: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupName(id: id, newName: newName)
        }
    }

    nonisolated
    func updateGroupIcon(id: String, newIcon: String?) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupIcon(id: id, newIcon: newIcon)
        }
    }

    nonisolated
    func deleteGroup(id: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.deleteGroup(id: id)
        }
    }

    nonisolated
    func updateGroupOrder(groupIDs: [String]) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupOrder(groupIDs: groupIDs)
        }
    }

    func moveItemToTop(id: UUID) async {
        await storeActor.updateItemTimestampToNow(id: id)
    }

    nonisolated
    func updateRecordText(
        hash: String,
        newText: String,
        newRTFData: Data? = nil,
        newRichTextArchiveData: Data? = nil
    ) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateRecordText(
                hash: hash,
                newText: newText,
                newRTFData: newRTFData,
                newRichTextArchiveData: newRichTextArchiveData
            )
        }
    }

    nonisolated
    func updateRecordCustomTitle(hash: String, customTitle: String?) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateRecordCustomTitle(hash: hash, customTitle: customTitle)
        }
    }

    func fetchGroups() async -> [ClipboardGroupItem] {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.fetchAllGroups()
        }
    }

    /// UI 驱动的分组读取(数据量极小)。
    /// 直接在 MainActor 上读 `mainContext`,避免 MainActor await
    /// `@ModelActor` (Background QoS) 造成的优先级反转 (Hang Risk)。
    @MainActor
    func fetchAllGroupsOnMain() -> [ClipboardGroupItem] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            ClipboardGroupItem(
                id: $0.id,
                name: $0.name,
                systemIconName: $0.resolvedSystemIconName,
                sortOrder: $0.sortOrder
            )
        }
    }

    func fetchItem(hash: String) async -> ClipboardItem? {
        let container = self.container
        let snapshot = await detachedRead { () -> ClipboardRecordSnapshot? in
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.fetchRecordSnapshot(hash: hash)
        }
        guard let snapshot else { return nil }
        return StorageManager.makeClipboardItem(from: snapshot)
    }

    func repairImportedMigrationTimestampsIfNeeded() async -> Int {
        await storeActor.repairImportedMigrationTimestampsIfNeeded()
    }

    func repairTextClassificationsIfNeeded() async -> Int {
        await storeActor.repairTextClassificationsIfNeeded()
    }

    func fetchDistinctAppBundleIDsForColorRepair() async -> [String] {
        await storeActor.fetchDistinctAppBundleIDsForColorRepair()
    }

    func repairAppIconDominantColors(using colorsByBundleID: [String: String]) async -> Int {
        await storeActor.repairAppIconDominantColors(using: colorsByBundleID)
    }

    func exportStore() async -> ClipboardStoreExport {
        let actor = storeActor
        return await detachedRead {
            await actor.exportStore()
        }
    }

    func importStoreExport(_ payload: ClipboardStoreExport) async throws {
        try await storeActor.importStoreExport(payload)
    }

    func loadPreviewImageData(id: UUID) async -> Data? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadPreviewImageData(id: id)
        }
    }

    func loadPlainText(id: UUID) async -> String? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadPlainText(id: id)
        }
    }

    func loadAppIconDominantColorHex(id: UUID) async -> String? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadAppIconDominantColorHex(id: id)
        }
    }

    func loadPasteRecord(id: UUID) async -> ClipboardPasteRecord? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadPasteRecord(id: id)
        }
    }

    func loadOriginalImageData(id: UUID) async -> Data? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadOriginalImageData(id: id)
        }
    }

    func loadImageData(id: UUID) async -> Data? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadImageData(id: id)
        }
    }

    func loadRTFData(id: UUID) async -> Data? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadRTFData(id: id)
        }
    }

    func loadImageUTType(id: UUID) async -> String? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadImageUTType(id: id)
        }
    }

    fileprivate nonisolated static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
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
            hasRTF: record.hasRTF
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

    nonisolated private func spawnTrackedTask(
        priority: TaskPriority,
        operation: @escaping @Sendable () async -> Void
    ) {
        let taskID = UUID()

        taskLock.lock()
        guard isShuttingDown == false else {
            taskLock.unlock()
            return
        }

        let task = Task.detached(priority: priority) { [weak self] in
            defer { self?.finishTrackedTask(id: taskID) }
            await operation()
        }

        activeTasks[taskID] = task
        taskLock.unlock()
    }

    nonisolated private func finishTrackedTask(id: UUID) {
        taskLock.lock()
        activeTasks.removeValue(forKey: id)
        taskLock.unlock()
    }

    nonisolated private func prepareForShutdown() -> [Task<Void, Never>] {
        taskLock.lock()
        defer { taskLock.unlock() }

        isShuttingDown = true
        return Array(activeTasks.values)
    }
}

@ModelActor
actor ClipboardStoreActor {
    func updateRecordWithRTFData(hash: String, rtfData: Data) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            guard record.richTextArchiveData == nil else {
                return
            }
            record.rtfData = rtfData
            try? modelContext.save()
        }
    }

    func updateRecordWithOCRText(hash: String, text: String) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            record.plainText = text
            try? modelContext.save()
        }
    }

    func updateRecordWithLinkMetadata(hash: String, title: String?, iconData: Data?) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            if let title { record.linkTitle = title }
            if let iconData { record.linkIconData = iconData }
            try? modelContext.save()
        }
    }

    func updateRecordCustomTitle(hash: String, customTitle: String?) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                let normalizedTitle = customTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                record.customTitle = normalizedTitle?.isEmpty == false ? normalizedTitle : nil
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.content.rawValue
                    ]
                )
            }
        } catch {
            print("❌ [ClipboardStoreActor] 标题更新失败: \(error)")
        }
    }

    fileprivate func fetchRecordSnapshot(hash: String) -> ClipboardRecordSnapshot? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1

        guard let record = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        let truncatedText: String? = {
            guard let text = record.plainText else { return nil }
            return text.count > 500 ? String(text.prefix(500)) : text
        }()

        return ClipboardRecordSnapshot(
            id: record.id,
            contentHash: record.contentHash,
            bundleIdentifier: record.appBundleID,
            appName: record.appLocalizedName ?? "Unknown App",
            timestamp: record.timestamp,
            plainText: truncatedText,
            hasPreviewImage: record.previewImageData != nil,
            hasImageData: record.imageData != nil,
            imageUTType: record.imageUTType,
            imagePixelWidth: record.imagePixelWidth,
            imagePixelHeight: record.imagePixelHeight,
            typeRawValue: record.typeRawValue,
            groupId: record.groupId,
            groupIdsRaw: record.groupIdsRaw,
            customTitle: record.customTitle,
            linkTitle: record.linkTitle,
            linkIconData: record.linkIconData,
            isPinned: record.isPinned,
            hasRTF: record.rtfData != nil
        )
    }

    func recordExists(hash: String) -> Bool {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first != nil
        } catch {
            print("❌ [ClipboardStoreActor] 查询失败: \(error)")
            return false
        }
    }

    func upsert(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        appIconDominantColorHex: String?,
        type: String,
        rtfData: Data?,
        richTextArchiveData: Data?,
        previewImageData: Data?,
        imageData: Data?,
        imageMetadata: ClipboardImageMetadata?
    ) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )

        do {
            let now = Date()

            if let existingRecord = try modelContext.fetch(descriptor).first {
                existingRecord.timestamp = now
                existingRecord.typeRawValue = type
                existingRecord.appBundleID = appID
                existingRecord.appLocalizedName = appName
                existingRecord.appIconDominantColorHex = appIconDominantColorHex

                if let text {
                    existingRecord.plainText = text
                } else if type != ClipboardContentType.image.rawValue {
                    existingRecord.plainText = nil
                }

                refreshStoredTextRepresentations(
                    for: existingRecord,
                    type: type,
                    rtfData: rtfData,
                    richTextArchiveData: richTextArchiveData
                )

                if let previewImageData {
                    existingRecord.previewImageData = previewImageData
                }

                if let imageData {
                    existingRecord.imageData = imageData
                }

                if let imageMetadata {
                    existingRecord.imageUTType = imageMetadata.utTypeIdentifier
                    existingRecord.imageByteCount = imageMetadata.byteCount
                    existingRecord.imagePixelWidth = imageMetadata.pixelWidth
                    existingRecord.imagePixelHeight = imageMetadata.pixelHeight
                }
            } else {
                let newRecord = ClipboardRecord(
                    timestamp: now,
                    contentHash: hash,
                    typeRawValue: type,
                    plainText: text,
                    previewImageData: previewImageData,
                    imageData: imageData,
                    imageMetadata: imageMetadata,
                    appBundleID: appID,
                    appLocalizedName: appName,
                    appIconDominantColorHex: appIconDominantColorHex,
                    rtfData: rtfData,
                    richTextArchiveData: richTextArchiveData
                )
                modelContext.insert(newRecord)
            }

            try modelContext.save()
            NotificationCenter.default.post(
                name: .clipboardRecordDidChange,
                object: nil,
                userInfo: [
                    "contentHash": hash,
                    "kind": ClipboardRecordChangeKind.upsert.rawValue
                ]
            )
        } catch {
            print("❌ [ClipboardStoreActor] 写入失败: \(error)")
        }
    }

    func cleanUpExpiredRecords(before expirationDate: Date) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.timestamp < expirationDate }
        )

        do {
            let expiredRecords = try modelContext.fetch(descriptor)
            guard !expiredRecords.isEmpty else { return }

            for record in expiredRecords {
                modelContext.delete(record)
            }

            try modelContext.save()
        } catch {
            print("❌ [清理任务] 清理过期记录失败: \(error)")
        }
    }

    func delete(hash: String) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        do {
            if let recordToDelete = try modelContext.fetch(descriptor).first {
                modelContext.delete(recordToDelete)
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.delete.rawValue
                    ]
                )
            }
        } catch {
            print("❌ [ClipboardStoreActor] 删除失败: \(error)")
        }
    }

    func deleteUnpinnedRecords() {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.isPinned == false }
        )
        do {
            let records = try modelContext.fetch(descriptor)
            guard !records.isEmpty else { return }

            for record in records {
                modelContext.delete(record)
            }

            try modelContext.save()
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        } catch {
            print("❌ [ClipboardStoreActor] 清空失败: \(error)")
        }
    }

    func createGroup(name: String, systemIconName: String? = nil) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        let minOrder = groups.map(\.sortOrder).min() ?? 0
        let newGroup = ClipboardGroupModel(name: name, systemIconName: systemIconName, sortOrder: minOrder - 1)
        modelContext.insert(newGroup)
        do {
            try modelContext.save()
        } catch {
            print("❌ [ClipboardStoreActor] 创建分组失败: \(error)")
        }
    }

    func assignRecordToGroup(recordHash: String, groupId: String) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == recordHash }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                var groupIDs = normalizedGroupIDs(primaryGroupID: record.groupId, groupIdsRaw: record.groupIdsRaw)
                if groupIDs.contains(groupId) == false {
                    groupIDs.append(groupId)
                }
                record.groupId = groupIDs.first
                record.groupIdsRaw = encodedGroupIDs(groupIDs)
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 分组分配失败: \(error)")
        }
    }

    func removeRecordFromGroup(recordHash: String, groupId: String) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == recordHash }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                var groupIDs = normalizedGroupIDs(primaryGroupID: record.groupId, groupIdsRaw: record.groupIdsRaw)
                groupIDs.removeAll { $0 == groupId }
                record.groupId = groupIDs.first
                record.groupIdsRaw = encodedGroupIDs(groupIDs)
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 移出分组失败: \(error)")
        }
    }

    func removeRecordFromAllGroups(recordHash: String) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == recordHash }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.groupId = nil
                record.groupIdsRaw = nil
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 清除分组失败: \(error)")
        }
    }

    func fetchAllGroups() -> [ClipboardGroupItem] {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let groups = (try? modelContext.fetch(descriptor)) ?? []

        return groups.map {
            ClipboardGroupItem(
                id: $0.id,
                name: $0.name,
                systemIconName: $0.resolvedSystemIconName,
                sortOrder: $0.sortOrder
            )
        }
    }

    func updateGroupName(id: String, newName: String) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.name = newName
            try? modelContext.save()
        }
    }

    func updateGroupIcon(id: String, newIcon: String?) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.systemIconName = ClipboardGroupIconName.storageValue(from: newIcon)
            try? modelContext.save()
        }
    }

    func deleteGroup(id: String) {
        let recordDescriptor = FetchDescriptor<ClipboardRecord>()
        if let records = try? modelContext.fetch(recordDescriptor) {
            for record in records {
                var groupIDs = normalizedGroupIDs(primaryGroupID: record.groupId, groupIdsRaw: record.groupIdsRaw)
                guard groupIDs.contains(id) else { continue }
                groupIDs.removeAll(where: { $0 == id })
                record.groupId = groupIDs.first
                record.groupIdsRaw = encodedGroupIDs(groupIDs)
            }
        }
        let groupDescriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(groupDescriptor).first {
            modelContext.delete(group)
        }
        try? modelContext.save()
    }

    func updateGroupOrder(groupIDs: [String]) {
        guard !groupIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<ClipboardGroupModel>()

        do {
            let groups = try modelContext.fetch(descriptor)
            let groupsById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

            for (index, id) in groupIDs.enumerated() {
                groupsById[id]?.sortOrder = index
            }

            let knownIDs = Set(groupIDs)
            let trailing = groups
                .filter { !knownIDs.contains($0.id) }
                .sorted { $0.sortOrder < $1.sortOrder }
            for (offset, group) in trailing.enumerated() {
                group.sortOrder = groupIDs.count + offset
            }

            try modelContext.save()
        } catch {
            print("❌ [ClipboardStoreActor] Group reorder failed: \(error)")
        }
    }

    func updateItemTimestampToNow(id: UUID) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.timestamp = Date()
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": record.contentHash,
                        "kind": ClipboardRecordChangeKind.reorder.rawValue
                    ]
                )
            }
        } catch {
            print("❌ [ClipboardStoreActor] 置顶时写入失败: \(error)")
        }
    }

    func updatePinStatus(hash: String, isPinned: Bool) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.isPinned = isPinned
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 固定状态更新失败: \(error)")
        }
    }

    func updateRecordText(
        hash: String,
        newText: String,
        newRTFData: Data? = nil,
        newRichTextArchiveData: Data? = nil
    ) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.plainText = newText
                if newRTFData != nil || newRichTextArchiveData != nil {
                    record.rtfData = newRTFData
                    record.richTextArchiveData = newRichTextArchiveData
                        ?? newRTFData.flatMap { ClipboardRichTextArchive.fromRTFData($0)?.encodedData() }
                }
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.content.rawValue
                    ]
                )
            }
        } catch {
            print("❌ [ClipboardStoreActor] 编辑保存失败: \(error)")
        }
    }

    func repairImportedMigrationTimestampsIfNeeded() -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let suspiciousUpperBound = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? .distantPast
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.timestamp < suspiciousUpperBound }
        )

        do {
            let records = try modelContext.fetch(descriptor)
            let migratedBundleIdentifiers = MigrationManager.migratedBundleIdentifiers
            let now = Date()
            var repairedCount = 0

            for record in records {
                guard let appBundleID = record.appBundleID,
                      migratedBundleIdentifiers.contains(appBundleID),
                      let repairedDate = MigrationManager.repairedDateIfLikelyMisdecodedReferenceTimestamp(
                        record.timestamp,
                        now: now
                      ) else {
                    continue
                }

                record.timestamp = repairedDate
                repairedCount += 1
            }

            if repairedCount > 0 {
                try modelContext.save()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复迁移时间戳失败: \(error)")
            return 0
        }
    }

    func repairTextClassificationsIfNeeded() async -> Int {
        let descriptor = FetchDescriptor<ClipboardRecord>()

        do {
            let records = try modelContext.fetch(descriptor)
            var repairedCount = 0

            for record in records {
                guard let text = record.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      text.isEmpty == false else {
                    continue
                }

                guard textBasedTypes.contains(record.typeRawValue) else {
                    continue
                }

                let reclassifiedType = await MainActor.run {
                    ClipboardContentClassifier.classify(text).rawValue
                }
                guard reclassifiedType != record.typeRawValue else {
                    continue
                }

                record.typeRawValue = reclassifiedType
                repairedCount += 1
            }

            if repairedCount > 0 {
                try modelContext.save()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复文本分类失败: \(error)")
            return 0
        }
    }

    func fetchDistinctAppBundleIDsForColorRepair() -> [String] {
        let descriptor = FetchDescriptor<ClipboardRecord>()

        do {
            let records = try modelContext.fetch(descriptor)
            var orderedBundleIDs: [String] = []
            var seenBundleIDs: Set<String> = []

            for record in records {
                guard let bundleID = record.appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      bundleID.isEmpty == false,
                      seenBundleIDs.insert(bundleID).inserted else {
                    continue
                }

                orderedBundleIDs.append(bundleID)
            }

            return orderedBundleIDs
        } catch {
            print("❌ [ClipboardStoreActor] 读取待修复 App 图标颜色失败: \(error)")
            return []
        }
    }

    func repairAppIconDominantColors(using colorsByBundleID: [String: String]) -> Int {
        guard colorsByBundleID.isEmpty == false else { return 0 }

        let descriptor = FetchDescriptor<ClipboardRecord>()

        do {
            let records = try modelContext.fetch(descriptor)
            var repairedCount = 0

            for record in records {
                guard let bundleID = record.appBundleID,
                      let repairedColor = colorsByBundleID[bundleID],
                      record.appIconDominantColorHex != repairedColor else {
                    continue
                }

                record.appIconDominantColorHex = repairedColor
                repairedCount += 1
            }

            if repairedCount > 0 {
                try modelContext.save()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复 App 图标主色失败: \(error)")
            return 0
        }
    }

    func exportStore() -> ClipboardStoreExport {
        let records = ((try? modelContext.fetch(FetchDescriptor<ClipboardRecord>())) ?? []).map {
            ClipboardRecordExport(
                id: $0.id,
                timestamp: $0.timestamp,
                contentHash: $0.contentHash,
                typeRawValue: $0.typeRawValue,
                plainText: $0.plainText,
                previewImageData: $0.previewImageData,
                imageData: $0.imageData,
                imageUTType: $0.imageUTType,
                imageByteCount: $0.imageByteCount,
                imagePixelWidth: $0.imagePixelWidth,
                imagePixelHeight: $0.imagePixelHeight,
                appBundleID: $0.appBundleID,
                appLocalizedName: $0.appLocalizedName,
                appIconDominantColorHex: $0.appIconDominantColorHex,
                groupId: $0.groupId,
                groupIdsRaw: $0.groupIdsRaw,
                customTitle: $0.customTitle,
                linkTitle: $0.linkTitle,
                linkIconData: $0.linkIconData,
                isPinned: $0.isPinned,
                rtfData: $0.rtfData,
                richTextArchiveData: $0.richTextArchiveData
            )
        }

        let groups = ((try? modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())) ?? []).map {
            ClipboardGroupExport(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                systemIconName: $0.resolvedSystemIconName,
                sortOrder: $0.sortOrder
            )
        }

        return ClipboardStoreExport(records: records, groups: groups)
    }

    func importStoreExport(_ payload: ClipboardStoreExport) throws {
        let existingGroups = (try? modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())) ?? []
        let groupsByID = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })

        for incomingGroup in payload.groups {
            if let existingGroup = groupsByID[incomingGroup.id] {
                existingGroup.name = incomingGroup.name
                existingGroup.systemIconName = ClipboardGroupIconName.storageValue(from: incomingGroup.systemIconName)
                existingGroup.sortOrder = incomingGroup.sortOrder
            } else {
                let group = ClipboardGroupModel(
                    id: incomingGroup.id,
                    name: incomingGroup.name,
                    systemIconName: incomingGroup.systemIconName,
                    sortOrder: incomingGroup.sortOrder
                )
                group.createdAt = incomingGroup.createdAt
                modelContext.insert(group)
            }
        }

        let existingRecords = (try? modelContext.fetch(FetchDescriptor<ClipboardRecord>())) ?? []
        var recordsByHash = Dictionary(existingRecords.map { ($0.contentHash, $0) }, uniquingKeysWith: { _, latest in latest })

        for incomingRecord in payload.records {
            if let existingRecord = recordsByHash[incomingRecord.contentHash] {
                existingRecord.timestamp = max(existingRecord.timestamp, incomingRecord.timestamp)
                existingRecord.typeRawValue = incomingRecord.typeRawValue
                existingRecord.appBundleID = incomingRecord.appBundleID ?? existingRecord.appBundleID
                existingRecord.appLocalizedName = incomingRecord.appLocalizedName ?? existingRecord.appLocalizedName
                existingRecord.appIconDominantColorHex = incomingRecord.appIconDominantColorHex ?? existingRecord.appIconDominantColorHex
                existingRecord.plainText = incomingRecord.plainText ?? existingRecord.plainText
                existingRecord.previewImageData = incomingRecord.previewImageData ?? existingRecord.previewImageData
                existingRecord.imageData = incomingRecord.imageData ?? existingRecord.imageData
                existingRecord.imageUTType = incomingRecord.imageUTType ?? existingRecord.imageUTType
                existingRecord.imageByteCount = incomingRecord.imageByteCount ?? existingRecord.imageByteCount
                existingRecord.imagePixelWidth = incomingRecord.imagePixelWidth ?? existingRecord.imagePixelWidth
                existingRecord.imagePixelHeight = incomingRecord.imagePixelHeight ?? existingRecord.imagePixelHeight
                existingRecord.customTitle = incomingRecord.customTitle ?? existingRecord.customTitle
                existingRecord.linkTitle = incomingRecord.linkTitle ?? existingRecord.linkTitle
                existingRecord.linkIconData = incomingRecord.linkIconData ?? existingRecord.linkIconData
                existingRecord.rtfData = incomingRecord.rtfData ?? existingRecord.rtfData
                existingRecord.richTextArchiveData = incomingRecord.richTextArchiveData ?? existingRecord.richTextArchiveData
                existingRecord.isPinned = existingRecord.isPinned || incomingRecord.isPinned

                var mergedGroupIDs = normalizedGroupIDs(
                    primaryGroupID: existingRecord.groupId,
                    groupIdsRaw: existingRecord.groupIdsRaw
                )
                let incomingGroupIDs = normalizedGroupIDs(
                    primaryGroupID: incomingRecord.groupId,
                    groupIdsRaw: incomingRecord.groupIdsRaw
                )
                for groupID in incomingGroupIDs where mergedGroupIDs.contains(groupID) == false {
                    mergedGroupIDs.append(groupID)
                }
                existingRecord.groupId = mergedGroupIDs.first
                existingRecord.groupIdsRaw = encodedGroupIDs(mergedGroupIDs)
            } else {
                let importedImageMetadata: ClipboardImageMetadata? = {
                    guard incomingRecord.imageData != nil
                            || incomingRecord.previewImageData != nil
                            || incomingRecord.imageUTType != nil
                            || incomingRecord.imageByteCount != nil
                            || incomingRecord.imagePixelWidth != nil
                            || incomingRecord.imagePixelHeight != nil else {
                        return nil
                    }

                    return ClipboardImageMetadata(
                        utTypeIdentifier: incomingRecord.imageUTType,
                        byteCount: incomingRecord.imageByteCount ?? incomingRecord.imageData?.count ?? 0,
                        pixelWidth: incomingRecord.imagePixelWidth,
                        pixelHeight: incomingRecord.imagePixelHeight
                    )
                }()

                let record = ClipboardRecord(
                    id: incomingRecord.id,
                    timestamp: incomingRecord.timestamp,
                    contentHash: incomingRecord.contentHash,
                    typeRawValue: incomingRecord.typeRawValue,
                    plainText: incomingRecord.plainText,
                    previewImageData: incomingRecord.previewImageData,
                    imageData: incomingRecord.imageData,
                    imageMetadata: importedImageMetadata,
                    appBundleID: incomingRecord.appBundleID,
                    appLocalizedName: incomingRecord.appLocalizedName,
                    appIconDominantColorHex: incomingRecord.appIconDominantColorHex,
                    groupId: incomingRecord.groupId,
                    groupIdsRaw: incomingRecord.groupIdsRaw,
                    customTitle: incomingRecord.customTitle,
                    linkTitle: incomingRecord.linkTitle,
                    linkIconData: incomingRecord.linkIconData,
                    isPinned: incomingRecord.isPinned,
                    rtfData: incomingRecord.rtfData,
                    richTextArchiveData: incomingRecord.richTextArchiveData
                )
                modelContext.insert(record)
                recordsByHash[incomingRecord.contentHash] = record
            }
        }

        try modelContext.save()
    }

    func loadPreviewImageData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.previewImageData
    }

    func loadPlainText(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.plainText
    }

    func loadAppIconDominantColorHex(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.appIconDominantColorHex
    }

    func loadPasteRecord(id: UUID) -> ClipboardPasteRecord? {
        guard let record = fetchStoredRecord(id: id) else {
            return nil
        }

        return ClipboardPasteRecord(
            id: record.id,
            typeRawValue: record.typeRawValue,
            plainText: record.plainText,
            rtfData: record.rtfData,
            richTextArchiveData: record.richTextArchiveData
        )
    }

    func loadOriginalImageData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.imageData
    }

    func loadImageData(id: UUID) -> Data? {
        if let record = fetchStoredRecord(id: id) {
            return record.imageData ?? record.previewImageData
        }
        return nil
    }

    func loadRTFData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.rtfData
    }

    func loadImageUTType(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.imageUTType
    }
}

private extension ClipboardStoreActor {
    nonisolated static let textBasedTypes: Set<String> = [
        ClipboardContentType.text.rawValue,
        ClipboardContentType.code.rawValue,
        ClipboardContentType.link.rawValue
    ]

    var textBasedTypes: Set<String> {
        Self.textBasedTypes
    }

    func refreshStoredTextRepresentations(
        for record: ClipboardRecord,
        type: String,
        rtfData: Data?,
        richTextArchiveData: Data?
    ) {
        let shouldRetainTextRepresentations = type != ClipboardContentType.image.rawValue
            && type != ClipboardContentType.fileURL.rawValue

        guard shouldRetainTextRepresentations else {
            record.rtfData = nil
            record.richTextArchiveData = nil
            return
        }

        record.rtfData = rtfData
        record.richTextArchiveData = richTextArchiveData
            ?? rtfData.flatMap { ClipboardRichTextArchive.fromRTFData($0)?.encodedData() }
    }

    func fetchStoredRecord(id: UUID) -> ClipboardRecord? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
