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
            return try distinctBundleIDs(
                matching: #Predicate<ClipboardRecord> { record in
                    record.appBundleID != nil
                }
            )
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
            return try distinctBundleIDs(
                matching: #Predicate<ClipboardRecord> { record in
                    record.appIconData == nil && record.appBundleID != nil
                }
            )
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

    private func distinctBundleIDs(matching predicate: Predicate<ClipboardRecord>) throws -> [String] {
        var orderedBundleIDs: [String] = []
        var seenBundleIDs: Set<String> = []

        try forEachRecordBatch(matching: predicate, readOnly: true) { records in
            for record in records {
                guard let bundleID = record.appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      bundleID.isEmpty == false,
                      seenBundleIDs.insert(bundleID).inserted else {
                    continue
                }

                orderedBundleIDs.append(bundleID)
            }
        }

        return orderedBundleIDs
    }
}
