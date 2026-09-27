import Foundation
import SwiftData

extension ClipboardStoreActor {
    func repairImportedMigrationTimestampsIfNeeded() -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let suspiciousUpperBound = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? .distantPast
        do {
            let migratedBundleIdentifiers = MigrationManager.migratedBundleIdentifiers
            let now = Date()
            var repairedCount = 0

            // 每次启动都会跑:只取可疑时间戳的行,不能再按页排序扫描整表(含内联大字段)。
            let descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: #Predicate<ClipboardRecord> { record in
                    record.timestamp < suspiciousUpperBound
                }
            )
            for record in try modelContext.fetch(descriptor) {
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
        let textTypes = Array(textBasedTypes)
        do {
            return try updateRecordsInBatches(
                matching: #Predicate<ClipboardRecord> { record in
                    record.plainText != nil && textTypes.contains(record.typeRawValue)
                }
            ) { record in
                guard let text = record.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      text.isEmpty == false else {
                    return false
                }

                let reclassifiedType = ClipboardContentClassifier.classify(text).rawValue
                guard reclassifiedType != record.typeRawValue else { return false }

                record.typeRawValue = reclassifiedType
                return true
            }
        } catch {
            print("❌ [ClipboardStoreActor] 修复文本分类失败: \(error)")
            return 0
        }
    }

    func fetchDistinctAppBundleIDsForColorRepair() -> [String] {
        do {
            var descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: #Predicate<ClipboardRecord> { record in
                    record.appBundleID != nil
                }
            )
            descriptor.propertiesToFetch = [\.appBundleID]
            return distinctBundleIDs(in: try modelContext.fetch(descriptor))
        } catch {
            print("❌ [ClipboardStoreActor] 读取待修复 App 图标颜色失败: \(error)")
            return []
        }
    }

    func repairAppIconDominantColors(using colorsByBundleID: [String: String]) -> Int {
        guard colorsByBundleID.isEmpty == false else { return 0 }

        let bundleIDs = Array(colorsByBundleID.keys)
        do {
            return try updateRecordsInBatches(
                matching: #Predicate<ClipboardRecord> { record in
                    record.appBundleID.flatMap { bundleIDs.contains($0) } ?? false
                }
            ) { record in
                guard let bundleID = record.appBundleID,
                      let repairedColor = colorsByBundleID[bundleID],
                      record.appIconDominantColorHex != repairedColor else {
                    return false
                }

                record.appIconDominantColorHex = repairedColor
                return true
            }
        } catch {
            print("❌ [ClipboardStoreActor] 修复 App 图标主色失败: \(error)")
            return 0
        }
    }

    func fetchDistinctAppBundleIDsMissingIconData() -> [String] {
        do {
            // 在 SQL 里判空,不触碰 externalStorage getter。
            var descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: #Predicate<ClipboardRecord> { record in
                    record.appIconData == nil && record.appBundleID != nil
                }
            )
            descriptor.propertiesToFetch = [\.appBundleID]
            return distinctBundleIDs(in: try modelContext.fetch(descriptor))
        } catch {
            print("❌ [ClipboardStoreActor] 读取待修复 App 图标数据失败: \(error)")
            return []
        }
    }

    func repairAppIconData(using iconDataByBundleID: [String: Data]) -> Int {
        guard iconDataByBundleID.isEmpty == false else { return 0 }

        let bundleIDs = Array(iconDataByBundleID.keys)
        do {
            return try updateRecordsInBatches(
                matching: #Predicate<ClipboardRecord> { record in
                    record.appBundleID.flatMap { bundleIDs.contains($0) } ?? false
                }
            ) { record in
                guard let bundleID = record.appBundleID,
                      let repairedIconData = iconDataByBundleID[bundleID],
                      record.appIconData != repairedIconData else {
                    return false
                }

                record.appIconData = repairedIconData
                return true
            }
        } catch {
            print("❌ [ClipboardStoreActor] 修复 App 图标数据失败: \(error)")
            return 0
        }
    }

    static let maintenanceBatchSize = 64

    /// 分批遍历匹配的记录并按批保存。`enumerate` 先取主键再按批加载整行,
    /// 不排序也不用 OFFSET;旧的"按 id 排序 + OFFSET"分页每页都要把整表
    /// (含内联大字段)重新排序一遍,几百 MB 的库会卡住几分钟。
    /// `update` 返回该记录是否被修改。
    func updateRecordsInBatches(
        matching predicate: Predicate<ClipboardRecord>? = nil,
        markingSyncAnchor: Bool = false,
        _ update: (ClipboardRecord) -> Bool
    ) throws -> Int {
        var visitedCount = 0
        var updatedCount = 0
        var pendingCount = 0

        func savePending() throws {
            guard pendingCount > 0 else { return }
            if markingSyncAnchor {
                try markSyncAnchorUpdated()
            }
            try modelContext.save()
            pendingCount = 0
        }

        try modelContext.enumerate(
            FetchDescriptor<ClipboardRecord>(predicate: predicate),
            batchSize: Self.maintenanceBatchSize
        ) { record in
            visitedCount += 1
            if update(record) {
                updatedCount += 1
                pendingCount += 1
            }
            if visitedCount % Self.maintenanceBatchSize == 0 {
                try savePending()
            }
        }
        try savePending()

        return updatedCount
    }

    private func distinctBundleIDs(in records: [ClipboardRecord]) -> [String] {
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
    }
}
