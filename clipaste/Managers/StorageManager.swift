import Foundation
import SwiftData

private struct ClipboardRecordSnapshot: Sendable {
    let id: UUID
    let contentHash: String
    let bundleIdentifier: String?
    let appName: String
    let timestamp: Date
    let plainText: String?
    let thumbnailPath: String?
    let originalFilePath: String?
    let typeRawValue: String
    let groupId: String?
    let groupIdsRaw: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let hasRTF: Bool          // ⚠️ 架构红线：仅轻量标记，不持有 RTF 二进制
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
            // ⚠️ 物理截断：plainText 最多 500 字符进入 UI 列表，严禁海量文本穿透
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
                thumbnailPath: record.thumbnailPath,
                originalFilePath: record.originalFilePath,
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
    nonisolated static let shared = StorageManager()
    nonisolated let container: ModelContainer
    private let storeActor: ClipboardStoreActor
    private let cleanupActor: ClipboardStoreActor

    private init() {
        do {
            let container = try ModelContainer(for: ClipboardRecord.self, ClipboardGroupModel.self)
            self.container = container
            self.storeActor = ClipboardStoreActor(modelContainer: container)
            self.cleanupActor = ClipboardStoreActor(modelContainer: container)
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    nonisolated
    func fetchItemsInBackground(searchText: String, container: ModelContainer) async -> [ClipboardItem] {
        let searcher = ClipboardSearcher(modelContainer: container)
        return await searcher.searchAndMap(searchText: searchText)
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
        thumbnailPath: String? = nil,
        originalFilePath: String? = nil
    ) {
        let actor = self.storeActor

        Task.detached(priority: .userInitiated) {
            await actor.upsert(
                hash: hash,
                text: text,
                appID: appID,
                appName: appName,
                type: type,
                thumbnailPath: thumbnailPath,
                originalFilePath: originalFilePath
            )
        }
    }

    /// Call from a @MainActor site: compute expirationDate there, pass the Date in.
    nonisolated
    func performAutoCleanup(before expirationDate: Date) {
        let actor = self.cleanupActor
        Task.detached(priority: .userInitiated) {
            await actor.cleanUpExpiredRecords(before: expirationDate)
        }
    }

    nonisolated
    func deleteRecord(hash: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.delete(hash: hash)
        }
    }

    /// 切换固定状态（不发送通知，ViewModel 已做乐观 UI 更新）
    nonisolated
    func togglePin(hash: String, isPinned: Bool) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.updatePinStatus(hash: hash, isPinned: isPinned)
        }
    }

    /// 在图片记录保存后，静默触发 OCR 任务，将提取出的文字回写至 plainText 以支持全局搜索。
    /// 参数 hash 即 contentHash，调用方在保存图片时就已经持有，无需再查询 UUID。
    nonisolated
    func processOCRForImage(hash: String, absoluteImagePath: String) {
        Task(priority: .background) {
            guard let text = await OCREngine.extractText(from: absoluteImagePath) else { return }
            let container = self.container
            let ocrActor = ClipboardStoreActor(modelContainer: container)
            await ocrActor.updateRecordWithOCRText(hash: hash, text: text)

            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        }
    }

    /// 对纯文本 URL 静默运行 LinkPresentation 抜取，成功后回写元数据并刷新 UI。
    nonisolated
    func processLinkMetadata(hash: String, urlString: String) {
        Task(priority: .background) {
            let (title, iconData) = await LinkMetadataEngine.fetchMetadata(for: urlString)
            guard title != nil || iconData != nil else { return }

            let container = self.container
            let linkActor = ClipboardStoreActor(modelContainer: container)
            await linkActor.updateRecordWithLinkMetadata(hash: hash, title: title, iconData: iconData)

            // 通知 UI 刷新，让生硅的链接卡片变成漂亮的书签
            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        }
    }

    /// 对纯文本记录静默运行 Highlightr 语法高亮，成功后回写 rtfData 并刷新 UI。
    nonisolated
    func processSyntaxHighlight(hash: String, text: String) {
        Task(priority: .background) {
            guard let rtfData = await SyntaxHighlightService.shared.processAndHighlight(text: text) else { return }
            let container = self.container
            let highlightActor = ClipboardStoreActor(modelContainer: container)
            await highlightActor.updateRecordWithRTFData(hash: hash, rtfData: rtfData)

            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        }
    }

    /// 彻底清空所有剪贴板历史，同时删除本地缓存的图片文件。
    /// Actor 完成后广播 `.clipboardDataDidChange`，ViewModel 的 Combine 订阅自动刺激 `loadData()` 清空 UI。
    nonisolated
    func clearAllHistory() {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.deleteAllRecords()
        }
    }

    nonisolated
    func createGroup(name: String, systemIconName: String = "folder") {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.createGroup(name: name, systemIconName: systemIconName)
        }
    }

    nonisolated
    func assignToGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.assignRecordToGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.removeRecordFromGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromAllGroups(hash: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.removeRecordFromAllGroups(recordHash: hash)
        }
    }

    nonisolated
    func renameGroup(id: String, newName: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.updateGroupName(id: id, newName: newName)
        }
    }

    nonisolated
    func updateGroupIcon(id: String, newIcon: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.updateGroupIcon(id: id, newIcon: newIcon)
        }
    }

    nonisolated
    func deleteGroup(id: String) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.deleteGroup(id: id)
        }
    }

    nonisolated
    func updateGroupOrder(groupIDs: [String]) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.updateGroupOrder(groupIDs: groupIDs)
        }
    }

    /// 将指定记录的时间戳刷新为当前时间，使其在按时间倒序排列时置顶。
    /// 更新完成后会广播 `.clipboardDataDidChange`，ViewModel 的 Combine 订阅会自动触发 UI 刷新。
    func moveItemToTop(id: UUID) async {
        await storeActor.updateItemTimestampToNow(id: id)
    }

    /// 更新记录的 plainText 和 RTF 数据（编辑保存时调用）
    nonisolated
    func updateRecordText(hash: String, newText: String, newRTFData: Data? = nil) {
        let actor = self.storeActor
        Task.detached(priority: .userInitiated) {
            await actor.updateRecordText(hash: hash, newText: newText, newRTFData: newRTFData)
        }
    }

    /// 异步读取所有分组（通过 Actor)
    func fetchGroups() async -> [ClipboardGroupItem] {
        await storeActor.fetchAllGroups()
    }

    /// 同步拉取所有分组（主线程 mainContext）
    @MainActor
    func fetchAllGroups() -> [ClipboardGroupItem] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { ClipboardGroupItem(id: $0.id, name: $0.name, systemIconName: $0.systemIconName, sortOrder: $0.sortOrder) }
    }

    @MainActor
    fileprivate static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        let id = record.id
        let contentHash = record.contentHash
        let bundleIdentifier = record.bundleIdentifier
        let appName = record.appName
        let timestamp = record.timestamp
        let plainText = record.plainText
        let thumbnailPath = record.thumbnailPath
        let type = ClipboardContentType(rawValue: record.typeRawValue) ?? .text
        let appIcon = bundleIdentifier.flatMap { AppIconManager.shared.getIcon(for: $0) }

        return ClipboardItem(
            id: id,
            contentType: type,
            contentHash: contentHash,
            textPreview: makeTextPreview(plainText: plainText, type: type),
            searchableText: plainText,
            sourceBundleIdentifier: bundleIdentifier,
            appName: appName,
            appIcon: appIcon,
            appIconName: ClipboardItem.appIconName(for: bundleIdentifier),
            timestamp: timestamp,
            rawText: (type == .text || type == .link || type == .code) ? plainText : nil,
            imagePath: type == .image ? thumbnailPath : nil,
            thumbnailURL: type == .image ? LocalFileManager.shared.url(forRelativePath: thumbnailPath) : nil,
            originalImageURL: type == .image ? LocalFileManager.shared.url(forRelativePath: record.originalFilePath) : nil,
            fileURL: type == .fileURL ? plainText : nil,
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
}

@ModelActor
actor ClipboardStoreActor {
    /// 将语法高亮后的 RTF 数据静默写入指定文本记录（通过 contentHash 查找记录）。
    func updateRecordWithRTFData(hash: String, rtfData: Data) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            record.rtfData = rtfData
            try? modelContext.save()
            print("✅ 语法高亮 RTF 已静默更新 (hash: \(hash.prefix(8))…)")
        }
    }

    /// 将 OCR 提取出的文字静默写入指定图片记录的 plainText 字段（通过 contentHash 查找记录）。
    func updateRecordWithOCRText(hash: String, text: String) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            record.plainText = text
            try? modelContext.save()
            print("✅ OCR 文本已静默更新至图片记录 (hash: \(hash.prefix(8))…)")
        }
    }

    /// 将 LinkPresentation 抓取到的网页标题和图标静默回写至指定文本记录。
    func updateRecordWithLinkMetadata(hash: String, title: String?, iconData: Data?) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            if let title { record.linkTitle = title }
            if let iconData { record.linkIconData = iconData }
            try? modelContext.save()
            print("✅ 链接元数据已静默更新: \(title ?? "未知标题") (hash: \(hash.prefix(8))…)")
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
        thumbnailPath: String?,
        originalFilePath: String?
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
                existingRecord.plainText = text
                existingRecord.appBundleID = appID
                existingRecord.appLocalizedName = appName

                if let thumbnailPath {
                    existingRecord.thumbnailPath = thumbnailPath
                }

                if let originalFilePath {
                    existingRecord.originalFilePath = originalFilePath
                }
            } else {
                let newRecord = ClipboardRecord(
                    timestamp: now,
                    contentHash: hash,
                    typeRawValue: type,
                    plainText: text,
                    thumbnailPath: thumbnailPath,
                    originalFilePath: originalFilePath,
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

            let fileManager = FileManager.default
            let localFileManager = LocalFileManager.shared

            for record in expiredRecords {
                // Delete associated image files to free disk space
                if record.typeRawValue == ClipboardContentType.image.rawValue {
                    if let thumbnailPath = record.thumbnailPath,
                       let url = localFileManager.url(forRelativePath: thumbnailPath) {
                        try? fileManager.removeItem(at: url)
                    }
                    if let originalPath = record.originalFilePath,
                       let url = localFileManager.url(forRelativePath: originalPath) {
                        try? fileManager.removeItem(at: url)
                    }
                }
                modelContext.delete(record)
            }

            try modelContext.save()
            print("✅ [清理任务] 成功清理了 \(expiredRecords.count) 条过期记录")
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
                // ⚠️ 不发送 .clipboardDataDidChange —— ViewModel 已做乐观移除，
                //    此处再触发 loadData() 会引发动画中数组二次突变，造成崩溃。
            }
        } catch {
            print("❌ [ClipboardStoreActor] 删除失败: \(error)")
        }
    }

    /// 彻底清空所有剪贴板记录及关联的本地图片文件。
    func deleteAllRecords() {
        let descriptor = FetchDescriptor<ClipboardRecord>()
        do {
            let records = try modelContext.fetch(descriptor)
            guard !records.isEmpty else {
                print("⚠️ [ClipboardStoreActor] 历史已空，无需清空")
                return
            }

            let localFileManager = LocalFileManager.shared
            let fileManager = FileManager.default

            for record in records {
                // \u987a\u624b\u5220\u9664\u672c\u5730\u7f29\u7565\u56fe\uff0c\u5f7b\u5e95\u91ca\u653e\u78c1\u76d8\u7a7a\u95f4
                if record.typeRawValue == ClipboardContentType.image.rawValue {
                    if let thumbnailPath = record.thumbnailPath,
                       let url = localFileManager.url(forRelativePath: thumbnailPath) {
                        try? fileManager.removeItem(at: url)
                    }
                    if let originalPath = record.originalFilePath,
                       let url = localFileManager.url(forRelativePath: originalPath) {
                        try? fileManager.removeItem(at: url)
                    }
                }
                modelContext.delete(record)
            }

            try modelContext.save()
            // \u5e7f\u64ad\u53d8\u66f4\u901a\u77e5\uff0cViewModel \u7684 Combine \u8ba2\u9605\u81ea\u52a8\u523a\u6fc0 loadData() \u6e05\u7a7a UI
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            print("✅ [ClipboardStoreActor] 已彻底清空 \(records.count) 条历史记录")
        } catch {
            print("❌ [ClipboardStoreActor] 清空失败: \(error)")
        }
    }

    // MARK: - 分组 CRUD

    func createGroup(name: String, systemIconName: String = "folder") {
        // 查询当前最小 sortOrder，新分组排在最前面
        let descriptor = FetchDescriptor<ClipboardGroupModel>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        let minOrder = groups.map(\.sortOrder).min() ?? 0
        let newGroup = ClipboardGroupModel(name: name, systemIconName: systemIconName, sortOrder: minOrder - 1)
        modelContext.insert(newGroup)
        do {
            try modelContext.save()
            print("✅ [ClipboardStoreActor] 分组已创建: \(name), sortOrder: \(minOrder - 1)")
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
        var groups = (try? modelContext.fetch(descriptor)) ?? []

        // 历史数据兼容：若所有分组 sortOrder 均为默认值 0，按 createdAt 升序赋值
        if groups.count > 1 && groups.allSatisfy({ $0.sortOrder == 0 }) {
            groups.sort { $0.createdAt < $1.createdAt }
            for (index, group) in groups.enumerated() {
                group.sortOrder = index
            }
            try? modelContext.save()
            print("✅ [ClipboardStoreActor] 历史分组 sortOrder 已初始化")
        }

        return groups.map { ClipboardGroupItem(id: $0.id, name: $0.name, systemIconName: $0.systemIconName, sortOrder: $0.sortOrder) }
    }

    func updateGroupName(id: String, newName: String) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.name = newName
            try? modelContext.save()
            print("[ClipboardStoreActor] Group renamed: \(newName)")
        }
    }

    func updateGroupIcon(id: String, newIcon: String) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.systemIconName = newIcon
            try? modelContext.save()
            print("[ClipboardStoreActor] Group icon updated: \(newIcon)")
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
        // 2. Delete the group itself
        let groupDescriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let group = try? modelContext.fetch(groupDescriptor).first {
            modelContext.delete(group)
        }
        try? modelContext.save()
        print("[ClipboardStoreActor] Group deleted: \(id)")
    }

    func updateGroupOrder(groupIDs: [String]) {
        guard !groupIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<ClipboardGroupModel>()

        do {
            let groups = try modelContext.fetch(descriptor)
            let groupsById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

            // 按传入的顺序重新赋值 sortOrder
            for (index, id) in groupIDs.enumerated() {
                groupsById[id]?.sortOrder = index
            }

            // 未在列表中的分组排在末尾
            let knownIDs = Set(groupIDs)
            let trailing = groups.filter { !knownIDs.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
            for (offset, group) in trailing.enumerated() {
                group.sortOrder = groupIDs.count + offset
            }

            try modelContext.save()
            print("[ClipboardStoreActor] Group sortOrder updated: \(groupIDs)")
        } catch {
            print("❌ [ClipboardStoreActor] Group reorder failed: \(error)")
        }
    }

    /// 将指定记录的 timestamp 更新为当前时间，并触发 UI 刷新通知。
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
                print("✅ [ClipboardStoreActor] 记录已置顶: \(id)")
            } else {
                print("⚠️ [ClipboardStoreActor] 置顶失败，未找到记录: \(id)")
            }
        } catch {
            print("❌ [ClipboardStoreActor] 置顶时写入失败: \(error)")
        }
    }

    /// 更新记录的固定状态（不发送通知，ViewModel 已做乐观 UI）
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

    /// 更新记录的 plainText 和 RTF 数据（编辑保存时调用）
    func updateRecordText(hash: String, newText: String, newRTFData: Data? = nil) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.plainText = newText
                if let rtfData = newRTFData {
                    record.rtfData = rtfData
                }
                try modelContext.save()
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
                print("✅ [ClipboardStoreActor] 编辑内容已保存 (hash: \(hash.prefix(8))…)")
            }
        } catch {
            print("❌ [ClipboardStoreActor] 编辑保存失败: \(error)")
        }
    }
}
