import Foundation
import SwiftData

@ModelActor
actor ClipboardStoreActor {
    func diagnosticsSnapshot() -> ClipboardStoreDiagnosticsSnapshot {
        let recordCount = (try? modelContext.fetchCount(FetchDescriptor<ClipboardRecord>())) ?? 0
        let activeGroupDescriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.deletedAt == nil
            }
        )
        let groupCount = (try? modelContext.fetchCount(activeGroupDescriptor)) ?? 0
        var descriptor = FetchDescriptor<ClipboardRecord>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        descriptor.fetchLimit = 5
        let latestRecords = (try? modelContext.fetch(descriptor)) ?? []
        let latestRecordFingerprints = latestRecords.map { record in
            [
                String(record.contentHash.prefix(12)),
                String(Int(record.timestamp.timeIntervalSince1970)),
                record.typeRawValue
            ].joined(separator: ":")
        }

        return ClipboardStoreDiagnosticsSnapshot(
            recordCount: recordCount,
            groupCount: groupCount,
            latestRecordFingerprints: latestRecordFingerprints
        )
    }

    func updateRecordWithRTFData(hash: String, rtfData: Data) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            guard record.richTextArchiveData == nil else {
                return
            }
            record.rtfData = rtfData
            try? markSyncAnchorUpdated()
            try? modelContext.save()
        }
    }

    func updateRecordWithOCRText(hash: String, text: String) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: text)
            record.plainText = storedText.inlineText
            record.fullTextData = storedText.fullTextData
            record.isPlainTextTruncated = storedText.isTruncated
            try? markSyncAnchorUpdated()
            try? modelContext.save()
        }
    }

    func updateRecordWithLinkMetadata(hash: String, title: String?, iconData: Data?) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            if let title { record.linkTitle = title }
            if let iconData { record.linkIconData = iconData }
            try? markSyncAnchorUpdated()
            try? modelContext.save()
        }
    }

    func updateRecordCustomTitle(hash: String, customTitle: String?) {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                let normalizedTitle = customTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                record.customTitle = normalizedTitle?.isEmpty == false ? normalizedTitle : nil
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
            print("❌ [ClipboardStoreActor] 标题更新失败: \(error)")
        }
    }

    func fetchRecordSnapshot(hash: String) -> ClipboardRecordSnapshot? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1

        guard let record = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        return ClipboardRecordSnapshot.makeFromRecord(record)
    }

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
}
