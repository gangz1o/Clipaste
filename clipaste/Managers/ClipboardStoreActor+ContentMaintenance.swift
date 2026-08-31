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
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                var repairedInPage = 0
                for record in records {
                    guard record.timestamp < suspiciousUpperBound,
                          let appBundleID = record.appBundleID,
                          migratedBundleIdentifiers.contains(appBundleID),
                          let repairedDate = MigrationManager.repairedDateIfLikelyMisdecodedReferenceTimestamp(
                            record.timestamp,
                            now: now
                          ) else {
                        continue
                    }

                    record.timestamp = repairedDate
                    repairedCount += 1
                    repairedInPage += 1
                }

                if repairedInPage > 0 {
                    try modelContext.save()
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复迁移时间戳失败: \(error)")
            return 0
        }
    }

    func repairTextClassificationsIfNeeded() async -> Int {
        do {
            var repairedCount = 0
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                var repairedInPage = 0
                for record in records {
                    guard let text = record.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          text.isEmpty == false,
                          textBasedTypes.contains(record.typeRawValue) else {
                        continue
                    }

                    let reclassifiedType = ClipboardContentClassifier.classify(text).rawValue
                    guard reclassifiedType != record.typeRawValue else { continue }

                    record.typeRawValue = reclassifiedType
                    repairedCount += 1
                    repairedInPage += 1
                }

                if repairedInPage > 0 {
                    try modelContext.save()
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
                await Task.yield()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复文本分类失败: \(error)")
            return 0
        }
    }

    func fetchDistinctAppBundleIDsForColorRepair() -> [String] {
        do {
            var orderedBundleIDs: [String] = []
            var seenBundleIDs: Set<String> = []
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                for record in records {
                    guard let bundleID = record.appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                          bundleID.isEmpty == false,
                          seenBundleIDs.insert(bundleID).inserted else {
                        continue
                    }

                    orderedBundleIDs.append(bundleID)
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return orderedBundleIDs
        } catch {
            print("❌ [ClipboardStoreActor] 读取待修复 App 图标颜色失败: \(error)")
            return []
        }
    }

    func repairAppIconDominantColors(using colorsByBundleID: [String: String]) -> Int {
        guard colorsByBundleID.isEmpty == false else { return 0 }

        do {
            var repairedCount = 0
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                var repairedInPage = 0
                for record in records {
                    guard let bundleID = record.appBundleID,
                          let repairedColor = colorsByBundleID[bundleID],
                          record.appIconDominantColorHex != repairedColor else {
                        continue
                    }

                    record.appIconDominantColorHex = repairedColor
                    repairedCount += 1
                    repairedInPage += 1
                }

                if repairedInPage > 0 {
                    try modelContext.save()
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复 App 图标主色失败: \(error)")
            return 0
        }
    }

    func fetchDistinctAppBundleIDsMissingIconData() -> [String] {
        do {
            var orderedBundleIDs: [String] = []
            var seenBundleIDs: Set<String> = []
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                for record in records {
                    guard record.appIconData == nil,
                          let bundleID = record.appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                          bundleID.isEmpty == false,
                          seenBundleIDs.insert(bundleID).inserted else {
                        continue
                    }

                    orderedBundleIDs.append(bundleID)
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return orderedBundleIDs
        } catch {
            print("❌ [ClipboardStoreActor] 读取待修复 App 图标数据失败: \(error)")
            return []
        }
    }

    func repairAppIconData(using iconDataByBundleID: [String: Data]) -> Int {
        guard iconDataByBundleID.isEmpty == false else { return 0 }

        do {
            var repairedCount = 0
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                var repairedInPage = 0
                for record in records {
                    guard let bundleID = record.appBundleID,
                          let repairedIconData = iconDataByBundleID[bundleID],
                          record.appIconData != repairedIconData else {
                        continue
                    }

                    record.appIconData = repairedIconData
                    repairedCount += 1
                    repairedInPage += 1
                }

                if repairedInPage > 0 {
                    try modelContext.save()
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复 App 图标数据失败: \(error)")
            return 0
        }
    }

    static let maintenancePageSize = 64

    func fetchRecordPage(offset: Int) throws -> [ClipboardRecord] {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = Self.maintenancePageSize
        return try modelContext.fetch(descriptor)
    }
}
