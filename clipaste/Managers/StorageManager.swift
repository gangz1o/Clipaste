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
    let typeRawValue: String
    let groupId: String?
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
            ClipboardRecordSnapshot(
                id: record.id,
                contentHash: record.contentHash,
                bundleIdentifier: record.appBundleID,
                appName: record.appLocalizedName ?? "Unknown App",
                timestamp: record.timestamp,
                plainText: record.plainText,
                thumbnailPath: record.thumbnailPath,
                typeRawValue: record.typeRawValue,
                groupId: record.groupId
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

    private init() {
        do {
            let container = try ModelContainer(for: ClipboardRecord.self, ClipboardGroupModel.self)
            self.container = container
            self.storeActor = ClipboardStoreActor(modelContainer: container)
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
        let container = self.container

        Task(priority: .userInitiated) {
            let storeActor = ClipboardStoreActor(modelContainer: container)

            await storeActor.upsert(
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

    nonisolated
    func deleteRecord(hash: String) {
        let actor = self.storeActor
        Task(priority: .userInitiated) {
            await actor.delete(hash: hash)
        }
    }

    nonisolated
    func createGroup(name: String, systemIconName: String = "folder") {
        let actor = self.storeActor
        Task(priority: .userInitiated) {
            await actor.createGroup(name: name, systemIconName: systemIconName)
        }
    }

    nonisolated
    func assignToGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        Task(priority: .userInitiated) {
            await actor.assignRecordToGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func renameGroup(id: String, newName: String) {
        let actor = self.storeActor
        Task(priority: .userInitiated) {
            await actor.updateGroupName(id: id, newName: newName)
        }
    }

    nonisolated
    func deleteGroup(id: String) {
        let actor = self.storeActor
        Task(priority: .userInitiated) {
            await actor.deleteGroup(id: id)
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
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { ClipboardGroupItem(id: $0.id, name: $0.name, systemIconName: $0.systemIconName) }
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
            sourceBundleIdentifier: bundleIdentifier,
            appName: appName,
            appIcon: appIcon,
            appIconName: ClipboardItem.appIconName(for: bundleIdentifier),
            timestamp: timestamp,
            rawText: type == .text ? plainText : nil,
            imagePath: type == .image ? thumbnailPath : nil,
            thumbnailURL: type == .image ? LocalFileManager.shared.url(forRelativePath: thumbnailPath) : nil,
            fileURL: type == .fileURL ? plainText : nil,
            groupId: record.groupId
        )
    }

    fileprivate static func makeTextPreview(plainText: String?, type: ClipboardContentType) -> String {
        switch type {
        case .text:
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
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        } catch {
            print("❌ [ClipboardStoreActor] 删除失败: \(error)")
        }
    }

    // MARK: - 分组 CRUD

    func createGroup(name: String, systemIconName: String = "folder") {
        let newGroup = ClipboardGroupModel(name: name, systemIconName: systemIconName)
        modelContext.insert(newGroup)
        do {
            try modelContext.save()
            print("✅ [ClipboardStoreActor] 分组已创建: \(name)")
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
                record.groupId = groupId
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 分组分配失败: \(error)")
        }
    }

    func fetchAllGroups() -> [ClipboardGroupItem] {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        return groups.map { ClipboardGroupItem(id: $0.id, name: $0.name, systemIconName: $0.systemIconName) }
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

    func deleteGroup(id: String) {
        // 1. Safely unbind all records in this group (set groupId = nil)
        let recordDescriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.groupId == id }
        )
        if let records = try? modelContext.fetch(recordDescriptor) {
            for record in records { record.groupId = nil }
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
}
