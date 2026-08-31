import Foundation
import SwiftData

extension StorageManager {
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
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.deletedAt == nil
            },
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

    func diagnosticsSnapshot() async -> ClipboardStoreDiagnosticsSnapshot {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.diagnosticsSnapshot()
        }
    }

    func repairImportedMigrationTimestampsIfNeeded() async -> Int {
        await storeActor.repairImportedMigrationTimestampsIfNeeded()
    }

    func repairTextClassificationsIfNeeded() async -> Int {
        await storeActor.repairTextClassificationsIfNeeded()
    }

    func touchSyncAnchor() async throws {
        try await storeActor.touchSyncAnchor()
    }

    func repairDuplicateRecords() async -> Int {
        await storeActor.repairDuplicateRecords()
    }

    func repairOversizedInlineTextRecords() async -> Int {
        await storeActor.repairOversizedInlineTextRecords()
    }

    func fetchDistinctAppBundleIDsForColorRepair() async -> [String] {
        await storeActor.fetchDistinctAppBundleIDsForColorRepair()
    }

    func repairAppIconDominantColors(using colorsByBundleID: [String: String]) async -> Int {
        await storeActor.repairAppIconDominantColors(using: colorsByBundleID)
    }

    func fetchDistinctAppBundleIDsMissingIconData() async -> [String] {
        await storeActor.fetchDistinctAppBundleIDsMissingIconData()
    }

    func repairAppIconData(using iconDataByBundleID: [String: Data]) async -> Int {
        await storeActor.repairAppIconData(using: iconDataByBundleID)
    }

    func exportGroups() async throws -> [ClipboardGroupExport] {
        let container = self.container
        return try await Task.detached(priority: .utility) {
            let actor = ClipboardStoreActor(modelContainer: container)
            return try await actor.exportGroups()
        }.value
    }

    func exportRecordBatch(offset: Int, limit: Int) async throws -> [ClipboardRecordExport] {
        let container = self.container
        return try await Task.detached(priority: .utility) {
            let actor = ClipboardStoreActor(modelContainer: container)
            return try await actor.exportRecordBatch(offset: offset, limit: limit)
        }.value
    }

    func exportPinnedRecordBatch(offset: Int, limit: Int) async throws -> ClipboardStoreExport {
        let container = self.container
        return try await Task.detached(priority: .utility) {
            let actor = ClipboardStoreActor(modelContainer: container)
            return try await actor.exportPinnedRecordBatch(offset: offset, limit: limit)
        }.value
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

    func loadAppIconData(id: UUID) async -> Data? {
        let container = self.container
        return await detachedRead {
            let actor = ClipboardStoreActor(modelContainer: container)
            return await actor.loadAppIconData(id: id)
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
}
