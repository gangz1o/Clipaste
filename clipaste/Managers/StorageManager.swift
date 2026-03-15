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
    let typeRawValue: String
    let groupId: String?
    let groupIdsRaw: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let hasRTF: Bool
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
    func searchAndMap(searchText: String) async -> [ClipboardItem] {
        let query = searchText
        let descriptor: FetchDescriptor<ClipboardRecord>

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
                typeRawValue: record.typeRawValue,
                groupId: record.groupId,
                groupIdsRaw: record.groupIdsRaw,
                linkTitle: record.linkTitle,
                linkIconData: record.linkIconData,
                isPinned: record.isPinned,
                hasRTF: record.rtfData != nil
            )
        }

        return await MainActor.run {
            snapshots.map(StorageManager.makeClipboardItem(from:))
        }
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

    nonisolated
    func fetchItemsInBackground(searchText: String, container: ModelContainer) async -> [ClipboardItem] {
        let searcher = ClipboardSearcher(modelContainer: container)
        return await searcher.searchAndMap(searchText: searchText)
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

    @MainActor
    func fetchRecord(id: UUID) -> ClipboardRecord? {
        let context = container.mainContext
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.id == id
            }
        )
        descriptor.fetchLimit = 1

        return try? context.fetch(descriptor).first
    }

    func recordExists(hash: String) async -> Bool {
        await storeActor.recordExists(hash: hash)
    }

    nonisolated
    func upsertRecord(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        type: String,
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
                type: type,
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
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
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
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
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
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        }
    }

    nonisolated
    func clearAllHistory() {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.deleteAllRecords()
        }
    }

    nonisolated
    func createGroup(name: String, systemIconName: String = "folder") {
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
    func updateGroupIcon(id: String, newIcon: String) {
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
    func updateRecordText(hash: String, newText: String, newRTFData: Data? = nil) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateRecordText(hash: hash, newText: newText, newRTFData: newRTFData)
        }
    }

    func fetchGroups() async -> [ClipboardGroupItem] {
        await storeActor.fetchAllGroups()
    }

    @MainActor
    func fetchAllGroups() -> [ClipboardGroupItem] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            ClipboardGroupItem(
                id: $0.id,
                name: $0.name,
                systemIconName: $0.systemIconName,
                sortOrder: $0.sortOrder
            )
        }
    }

    func exportStore() async -> ClipboardStoreExport {
        await storeActor.exportStore()
    }

    func importStoreExport(_ payload: ClipboardStoreExport) async throws {
        try await storeActor.importStoreExport(payload)
    }

    func loadPreviewImageData(id: UUID) async -> Data? {
        await storeActor.loadPreviewImageData(id: id)
    }

    func loadImageData(id: UUID) async -> Data? {
        await storeActor.loadImageData(id: id)
    }

    func loadImageUTType(id: UUID) async -> String? {
        await storeActor.loadImageUTType(id: id)
    }

    @MainActor
    fileprivate static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        let type = ClipboardContentType(rawValue: record.typeRawValue) ?? .text
        let appIcon = record.bundleIdentifier.flatMap { AppIconManager.shared.getIcon(for: $0) }

        return ClipboardItem(
            id: record.id,
            contentType: type,
            contentHash: record.contentHash,
            textPreview: makeTextPreview(plainText: record.plainText, type: type),
            searchableText: record.plainText,
            sourceBundleIdentifier: record.bundleIdentifier,
            appName: record.appName,
            appIcon: appIcon,
            appIconName: ClipboardItem.appIconName(for: record.bundleIdentifier),
            timestamp: record.timestamp,
            rawText: (type == .text || type == .link || type == .code) ? record.plainText : nil,
            hasImagePreview: record.hasPreviewImage,
            hasImageData: record.hasImageData,
            imageUTType: record.imageUTType,
            fileURL: type == .fileURL ? record.plainText : nil,
            groupId: record.groupId,
            groupIDs: normalizedGroupIDs(primaryGroupID: record.groupId, groupIdsRaw: record.groupIdsRaw),
            linkTitle: record.linkTitle,
            linkIconData: record.linkIconData,
            isPinned: record.isPinned,
            hasRTF: record.hasRTF
        )
    }

    fileprivate static func makeTextPreview(plainText: String?, type: ClipboardContentType) -> String {
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
        type: String,
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

                if let text {
                    existingRecord.plainText = text
                } else if type != ClipboardContentType.image.rawValue {
                    existingRecord.plainText = nil
                }

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
                    appLocalizedName: appName
                )
                modelContext.insert(newRecord)
            }

            try modelContext.save()
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
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
            }
        } catch {
            print("❌ [ClipboardStoreActor] 删除失败: \(error)")
        }
    }

    func deleteAllRecords() {
        let descriptor = FetchDescriptor<ClipboardRecord>()
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

    func createGroup(name: String, systemIconName: String = "folder") {
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
                systemIconName: $0.systemIconName,
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

    func updateGroupIcon(id: String, newIcon: String) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.systemIconName = newIcon
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
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
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

    func updateRecordText(hash: String, newText: String, newRTFData: Data? = nil) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.plainText = newText
                if let newRTFData {
                    record.rtfData = newRTFData
                }
                try modelContext.save()
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        } catch {
            print("❌ [ClipboardStoreActor] 编辑保存失败: \(error)")
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
                groupId: $0.groupId,
                groupIdsRaw: $0.groupIdsRaw,
                linkTitle: $0.linkTitle,
                linkIconData: $0.linkIconData,
                isPinned: $0.isPinned,
                rtfData: $0.rtfData
            )
        }

        let groups = ((try? modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())) ?? []).map {
            ClipboardGroupExport(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                systemIconName: $0.systemIconName,
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
                existingGroup.systemIconName = incomingGroup.systemIconName
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
        var recordsByHash = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.contentHash, $0) })

        for incomingRecord in payload.records {
            if let existingRecord = recordsByHash[incomingRecord.contentHash] {
                existingRecord.timestamp = max(existingRecord.timestamp, incomingRecord.timestamp)
                existingRecord.typeRawValue = incomingRecord.typeRawValue
                existingRecord.appBundleID = incomingRecord.appBundleID ?? existingRecord.appBundleID
                existingRecord.appLocalizedName = incomingRecord.appLocalizedName ?? existingRecord.appLocalizedName
                existingRecord.plainText = incomingRecord.plainText ?? existingRecord.plainText
                existingRecord.previewImageData = incomingRecord.previewImageData ?? existingRecord.previewImageData
                existingRecord.imageData = incomingRecord.imageData ?? existingRecord.imageData
                existingRecord.imageUTType = incomingRecord.imageUTType ?? existingRecord.imageUTType
                existingRecord.imageByteCount = incomingRecord.imageByteCount ?? existingRecord.imageByteCount
                existingRecord.imagePixelWidth = incomingRecord.imagePixelWidth ?? existingRecord.imagePixelWidth
                existingRecord.imagePixelHeight = incomingRecord.imagePixelHeight ?? existingRecord.imagePixelHeight
                existingRecord.linkTitle = incomingRecord.linkTitle ?? existingRecord.linkTitle
                existingRecord.linkIconData = incomingRecord.linkIconData ?? existingRecord.linkIconData
                existingRecord.rtfData = incomingRecord.rtfData ?? existingRecord.rtfData
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
                    groupId: incomingRecord.groupId,
                    groupIdsRaw: incomingRecord.groupIdsRaw,
                    linkTitle: incomingRecord.linkTitle,
                    linkIconData: incomingRecord.linkIconData,
                    isPinned: incomingRecord.isPinned,
                    rtfData: incomingRecord.rtfData
                )
                modelContext.insert(record)
                recordsByHash[incomingRecord.contentHash] = record
            }
        }

        try modelContext.save()
    }

    func loadPreviewImageData(id: UUID) -> Data? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.previewImageData
    }

    func loadImageData(id: UUID) -> Data? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            return record.imageData ?? record.previewImageData
        }
        return nil
    }

    func loadImageUTType(id: UUID) -> String? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.imageUTType
    }
}
