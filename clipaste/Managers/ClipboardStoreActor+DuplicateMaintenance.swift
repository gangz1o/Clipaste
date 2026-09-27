import Foundation
import SwiftData

extension ClipboardStoreActor {
    func repairDuplicateRecords() -> Int {
        // 分组表极小,顺带收拢同 ID 的分组墓碑。
        _ = repairDuplicateGroups()

        // Two passes:
        // 1) Batched scan (see forEachRecordBatch) recording which rows share a
        //    contentHash. The old sorted + OFFSET paging made SQLite re-sort the
        //    whole table (inline blobs included) per page and hung startup.
        // 2) Load only the rows of duplicate hashes and merge them.
        do {
            var identifiersByHash: [String: [PersistentIdentifier]] = [:]
            identifiersByHash.reserveCapacity(4096)
            try forEachRecordBatch(batchSize: 256, readOnly: true) { records in
                for record in records {
                    let contentHash = record.contentHash
                    guard contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
                    identifiersByHash[contentHash, default: []].append(record.persistentModelID)
                }
            }

            let duplicateHashes = identifiersByHash.compactMap { $0.value.count > 1 ? $0.key : nil }
            guard duplicateHashes.isEmpty == false else { return 0 }

            var repairedCount = 0

            let chunkSize = 200
            for chunkStart in stride(from: 0, to: duplicateHashes.count, by: chunkSize) {
                let hashChunk = Array(duplicateHashes[chunkStart..<min(chunkStart + chunkSize, duplicateHashes.count)])
                let records: [ClipboardRecord]
                if #available(macOS 15, *) {
                    records = try fetchRecords(identifiers: hashChunk.flatMap { identifiersByHash[$0] ?? [] })
                } else {
                    // macOS 14 不能按主键批量取,退回按 contentHash 查询(每批一次全表扫描)。
                    records = try modelContext.fetch(
                        FetchDescriptor<ClipboardRecord>(
                            predicate: #Predicate<ClipboardRecord> { record in
                                hashChunk.contains(record.contentHash)
                            }
                        )
                    )
                }

                for duplicates in Dictionary(grouping: records, by: \.contentHash).values where duplicates.count > 1 {
                    let orderedRecords = duplicates.sorted(by: shouldPreferSurvivor)
                    guard let survivor = orderedRecords.first else { continue }

                    for duplicate in orderedRecords.dropFirst() {
                        merge(duplicate, into: survivor)
                        modelContext.delete(duplicate)
                        repairedCount += 1
                    }
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
            return try updateRecordsInBatches(
                matching: #Predicate<ClipboardRecord> { record in
                    record.plainText != nil
                },
                markingSyncAnchor: true
            ) { record in
                guard let text = record.plainText,
                      text.utf8.count > ClipboardTextSyncPolicy.inlineLimitBytes else {
                    return false
                }

                let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: text)
                record.plainText = storedText.inlineText
                record.fullTextData = storedText.fullTextData
                record.isPlainTextTruncated = storedText.isTruncated
                return true
            }
        } catch {
            print("❌ [ClipboardStoreActor] 修复超大文本记录失败: \(error)")
            return 0
        }
    }
}
