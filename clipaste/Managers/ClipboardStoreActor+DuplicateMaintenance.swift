import Foundation
import SwiftData

extension ClipboardStoreActor {
    func repairDuplicateRecords() -> Int {
        // Two passes:
        // 1) Scan with batched fetch to identify which contentHashes have >1 row.
        //    We don't keep references to records here — let the context drop
        //    intermediate faults so memory stays flat regardless of table size.
        // 2) Only fetch and merge the small subset of records belonging to a
        //    duplicate hash.
        do {
            var counts: [String: Int] = [:]
            counts.reserveCapacity(4096)

            let pageSize = 256
            var offset = 0

            while true {
                var descriptor = FetchDescriptor<ClipboardRecord>(
                    sortBy: [
                        SortDescriptor(\.timestamp, order: .reverse),
                        SortDescriptor(\.id, order: .forward)
                    ]
                )
                descriptor.fetchLimit = pageSize
                descriptor.fetchOffset = offset

                let records = try modelContext.fetch(descriptor)
                guard records.isEmpty == false else { break }

                for record in records {
                    let contentHash = record.contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard contentHash.isEmpty == false else { continue }
                    counts[contentHash, default: 0] += 1
                }

                offset += records.count
                guard records.count == pageSize else { break }
            }

            let duplicateHashes = counts.compactMap { $0.value > 1 ? $0.key : nil }
            guard duplicateHashes.isEmpty == false else { return 0 }

            var repairedCount = 0

            for hash in duplicateHashes {
                let dupDescriptor = FetchDescriptor<ClipboardRecord>(
                    predicate: #Predicate<ClipboardRecord> { record in
                        record.contentHash == hash
                    }
                )
                let duplicates = (try? modelContext.fetch(dupDescriptor)) ?? []
                guard duplicates.count > 1 else { continue }

                let orderedRecords = duplicates.sorted(by: shouldPreferSurvivor)
                guard let survivor = orderedRecords.first else { continue }

                for duplicate in orderedRecords.dropFirst() {
                    merge(duplicate, into: survivor)
                    modelContext.delete(duplicate)
                    repairedCount += 1
                }
            }

            if repairedCount > 0 {
                try markSyncAnchorUpdated()
                try modelContext.save()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复重复记录失败: \(error)")
            return 0
        }
    }

    /// 把存量的超限内联文本迁移到 fullTextData(CKAsset 形态)。
    /// 单条超过 CloudKit 1MB 内联上限的记录会让整个导出队列卡死,
    /// 这个一次性修复能在不删数据的前提下疏通同步。
    func repairOversizedInlineTextRecords() -> Int {
        do {
            var repairedCount = 0
            var offset = 0

            while true {
                let records = try fetchRecordPage(offset: offset)
                guard records.isEmpty == false else { break }

                var repairedInPage = 0
                for record in records {
                    guard let text = record.plainText,
                          text.utf8.count > ClipboardTextSyncPolicy.inlineLimitBytes else {
                        continue
                    }

                    let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: text)
                    record.plainText = storedText.inlineText
                    record.fullTextData = storedText.fullTextData
                    record.isPlainTextTruncated = storedText.isTruncated
                    repairedCount += 1
                    repairedInPage += 1
                }

                if repairedInPage > 0 {
                    try markSyncAnchorUpdated()
                    try modelContext.save()
                }
                offset += records.count
                guard records.count == Self.maintenancePageSize else { break }
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复超大文本记录失败: \(error)")
            return 0
        }
    }
}
