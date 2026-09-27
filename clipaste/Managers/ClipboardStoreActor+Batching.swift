import Foundation
import SwiftData

extension ClipboardStoreActor {
    static let maintenanceBatchSize = 64

    /// 分批读取匹配的记录,内存上限为一批。
    ///
    /// macOS 15+:`fetchIdentifiers` 只执行一次 `SELECT Z_PK`,再按主键(`Z_PK IN`)逐批取整行。
    /// 不能用 `propertiesToFetch` 或 `enumerate` 代替:返回模型对象时 SwiftData 会忽略
    /// `propertiesToFetch`,`enumerate` 也会一次读完全部匹配行(含内联大字段)。
    ///
    /// macOS 14 没有 `fetchIdentifiers`,回退到"按 id 排序 + OFFSET"分页:每页都会重排整表,
    /// 较慢但内存同样只有一批。`body` 的修改不能让记录移出 `predicate` 的结果集,否则会漏页。
    ///
    /// `readOnly` 时每批使用新的 ModelContext:同一个 context 会一直持有读过的记录,
    /// 整表扫描时内存随表增长。只读遍历的 `body` 不能跨批保留记录对象。
    /// 写入必须留在共享的 `modelContext`,避免两个 context 改同一行时保存冲突。
    func forEachRecordBatch(
        matching predicate: Predicate<ClipboardRecord>? = nil,
        batchSize: Int = maintenanceBatchSize,
        readOnly: Bool = false,
        _ body: ([ClipboardRecord]) throws -> Void
    ) throws {
        guard batchSize > 0 else { return }

        func batchContext() -> ModelContext {
            readOnly ? ModelContext(modelContainer) : modelContext
        }

        if #available(macOS 15, *) {
            let identifiers = try fetchRecordIdentifiers(matching: predicate)
            for start in stride(from: 0, to: identifiers.count, by: batchSize) {
                let chunk = Array(identifiers[start..<min(start + batchSize, identifiers.count)])
                try body(fetchRecords(identifiers: chunk, in: batchContext()))
            }
            return
        }

        var offset = 0
        while true {
            var descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.id, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            let records = try batchContext().fetch(descriptor)
            guard records.isEmpty == false else { break }

            try body(records)
            offset += records.count
            guard records.count == batchSize else { break }
        }
    }

    /// 分批遍历匹配的记录,每批有修改时保存一次。`update` 返回该记录是否被修改。
    func updateRecordsInBatches(
        matching predicate: Predicate<ClipboardRecord>? = nil,
        markingSyncAnchor: Bool = false,
        _ update: (ClipboardRecord) -> Bool
    ) throws -> Int {
        var updatedCount = 0

        try forEachRecordBatch(matching: predicate) { records in
            var updatedInBatch = 0
            for record in records {
                if update(record) {
                    updatedInBatch += 1
                }
            }

            guard updatedInBatch > 0 else { return }
            if markingSyncAnchor {
                try markSyncAnchorUpdated()
            }
            try modelContext.save()
            updatedCount += updatedInBatch
        }

        return updatedCount
    }

    @available(macOS 15, *)
    func fetchRecordIdentifiers(
        matching predicate: Predicate<ClipboardRecord>? = nil,
        sortBy: [SortDescriptor<ClipboardRecord>] = []
    ) throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<ClipboardRecord>(predicate: predicate, sortBy: sortBy)
        // 带排序的 fetchIdentifiers 不支持未保存的改动;维护与导出都只看已保存的数据。
        descriptor.includePendingChanges = false
        return try modelContext.fetchIdentifiers(descriptor)
    }

    /// 按主键取行并保持 `identifiers` 的顺序;快照之后已删除的记录直接跳过。
    @available(macOS 15, *)
    func fetchRecords(
        identifiers: [PersistentIdentifier],
        in context: ModelContext? = nil
    ) throws -> [ClipboardRecord] {
        guard identifiers.isEmpty == false else { return [] }

        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                identifiers.contains(record.persistentModelID)
            }
        )
        let recordsByID = Dictionary(
            try (context ?? modelContext).fetch(descriptor).map { ($0.persistentModelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { recordsByID[$0] }
    }
}
