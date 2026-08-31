import Foundation
import SwiftData

extension ClipboardStoreActor {
    func createGroup(name: String, systemIconName: String? = nil) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.deletedAt == nil
            }
        )
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        let minOrder = groups.map(\.sortOrder).min() ?? 0
        let newGroup = ClipboardGroupModel(name: name, systemIconName: systemIconName, sortOrder: minOrder - 1)
        modelContext.insert(newGroup)
        do {
            try markSyncAnchorUpdated()
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
                try markSyncAnchorUpdated()
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
                try markSyncAnchorUpdated()
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
                try markSyncAnchorUpdated()
                try modelContext.save()
            }
        } catch {
            print("❌ [ClipboardStoreActor] 清除分组失败: \(error)")
        }
    }

    func fetchAllGroups() -> [ClipboardGroupItem] {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.deletedAt == nil
            },
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
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.id == id && group.deletedAt == nil
            }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.name = newName
            try? markSyncAnchorUpdated()
            try? modelContext.save()
        }
    }

    func updateGroupIcon(id: String, newIcon: String?) {
        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.id == id && group.deletedAt == nil
            }
        )
        if let group = try? modelContext.fetch(descriptor).first {
            group.systemIconName = ClipboardGroupIconName.storageValue(from: newIcon)
            try? markSyncAnchorUpdated()
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
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.id == id && group.deletedAt == nil
            }
        )
        if let group = try? modelContext.fetch(groupDescriptor).first {
            group.markDeleted()
        }
        try? markSyncAnchorUpdated()
        try? modelContext.save()
    }

    func updateGroupOrder(groupIDs: [String]) {
        guard !groupIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.deletedAt == nil
            }
        )

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

            try markSyncAnchorUpdated()
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
                try markSyncAnchorUpdated()
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
                try markSyncAnchorUpdated()
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
                let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: newText)
                record.plainText = storedText.inlineText
                record.fullTextData = storedText.fullTextData
                record.isPlainTextTruncated = storedText.isTruncated
                if newRTFData != nil || newRichTextArchiveData != nil {
                    record.rtfData = newRTFData
                    record.richTextArchiveData = newRichTextArchiveData
                        ?? newRTFData.flatMap { ClipboardRichTextArchive.fromRTFData($0)?.encodedData() }
                }
                try markSyncAnchorUpdated()
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

    func touchSyncAnchor() throws {
        try markSyncAnchorUpdated(force: true)
        try modelContext.save()
    }
}
