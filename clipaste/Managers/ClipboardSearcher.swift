import Foundation
import SwiftData

@ModelActor
actor ClipboardSearcher {
    func searchAndMap(searchText: String, fetchLimit: Int? = nil, offset: Int = 0) async -> [ClipboardItem] {
        let query = searchText
        var descriptor: FetchDescriptor<ClipboardRecord>

        if query.isEmpty {
            descriptor = FetchDescriptor<ClipboardRecord>(
                sortBy: [
                    SortDescriptor(\.topPinOrder, order: .reverse),
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .forward)
                ]
            )
        } else {
            let predicate = #Predicate<ClipboardRecord> { record in
                (record.plainText?.localizedStandardContains(query) == true) ||
                (record.appLocalizedName?.localizedStandardContains(query) == true)
            }

            descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.topPinOrder, order: .reverse),
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .forward)
                ]
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
            ClipboardRecordSnapshot.makeFromRecord(record)
        }

        return snapshots.map { StorageManager.makeClipboardItem(from: $0) }
    }

    /// 按筛选范围（自建分组 / 收藏 / 类型）直查数据库，可叠加搜索词。
    /// 只用一个最具选择性的范围条件做谓词，其余范围条件交给调用方在内存里取交集。
    func fetchScoped(
        searchText: String,
        groupId: String?,
        typeRawValue: String?,
        favoritesOnly: Bool,
        fetchLimit: Int
    ) async -> [ClipboardItem] {
        guard var descriptor = Self.scopedDescriptor(
            query: searchText,
            groupId: groupId,
            typeRawValue: typeRawValue,
            favoritesOnly: favoritesOnly
        ) else {
            return []
        }

        if fetchLimit > 0 {
            descriptor.fetchLimit = fetchLimit
        }

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = records.map { record in
            ClipboardRecordSnapshot.makeFromRecord(record)
        }

        return snapshots.map { StorageManager.makeClipboardItem(from: $0) }
    }

    // #Predicate 不能按条件拼接，范围 × 是否带搜索词逐一展开。
    // groupIdsRaw 是 JSON 编码的 ID 数组，按子串匹配 UUID 不会误命中。
    private static func scopedDescriptor(
        query: String,
        groupId: String?,
        typeRawValue: String?,
        favoritesOnly: Bool
    ) -> FetchDescriptor<ClipboardRecord>? {
        let sortBy = [
            SortDescriptor(\ClipboardRecord.topPinOrder, order: .reverse),
            SortDescriptor(\ClipboardRecord.timestamp, order: .reverse),
            SortDescriptor(\ClipboardRecord.id, order: .forward)
        ]
        let hasQuery = query.isEmpty == false

        if let groupId, groupId.isEmpty == false {
            let predicate = hasQuery
                ? #Predicate<ClipboardRecord> { record in
                    (record.groupId == groupId || (record.groupIdsRaw?.contains(groupId) == true)) &&
                    ((record.plainText?.localizedStandardContains(query) == true) ||
                     (record.appLocalizedName?.localizedStandardContains(query) == true))
                }
                : #Predicate<ClipboardRecord> { record in
                    record.groupId == groupId || (record.groupIdsRaw?.contains(groupId) == true)
                }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }

        if favoritesOnly {
            let predicate = hasQuery
                ? #Predicate<ClipboardRecord> { record in
                    record.isPinned == true &&
                    ((record.plainText?.localizedStandardContains(query) == true) ||
                     (record.appLocalizedName?.localizedStandardContains(query) == true))
                }
                : #Predicate<ClipboardRecord> { record in record.isPinned == true }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }

        if let typeRawValue {
            let predicate = hasQuery
                ? #Predicate<ClipboardRecord> { record in
                    record.typeRawValue == typeRawValue &&
                    ((record.plainText?.localizedStandardContains(query) == true) ||
                     (record.appLocalizedName?.localizedStandardContains(query) == true))
                }
                : #Predicate<ClipboardRecord> { record in record.typeRawValue == typeRawValue }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }

        return nil
    }
}
