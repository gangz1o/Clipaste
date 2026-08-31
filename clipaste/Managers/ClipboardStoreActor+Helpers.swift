import Foundation
import SwiftData

extension ClipboardStoreActor {
    nonisolated static let syncAnchorID = "global"
    nonisolated static let minimumSyncAnchorNudgeInterval: TimeInterval = 2
    nonisolated static let textBasedTypes: Set<String> = [
        ClipboardContentType.text.rawValue,
        ClipboardContentType.code.rawValue,
        ClipboardContentType.link.rawValue
    ]

    var textBasedTypes: Set<String> {
        Self.textBasedTypes
    }

    func markSyncAnchorUpdated(force: Bool = false) throws {
        let anchorID = Self.syncAnchorID
        var descriptor = FetchDescriptor<SyncAnchor>(
            predicate: #Predicate<SyncAnchor> { anchor in
                anchor.id == anchorID
            }
        )
        descriptor.fetchLimit = 1

        let anchor: SyncAnchor
        if let existingAnchor = try modelContext.fetch(descriptor).first {
            anchor = existingAnchor
        } else {
            anchor = SyncAnchor(id: Self.syncAnchorID)
            modelContext.insert(anchor)
        }

        let now = Date()
        if force == false, now.timeIntervalSince(anchor.updatedAt) < Self.minimumSyncAnchorNudgeInterval {
            return
        }

        anchor.updatedAt = now
        anchor.platform = ClipboardSourceMetadata.currentPlatform
        anchor.deviceName = ClipboardSourceMetadata.currentDeviceName ?? ""
        anchor.generation = UUID()
    }

    /// 归一化导入负载中的文本三元组。返回 nil 表示来源没有文本(合并时保留现值)。
    /// 老版本导出的负载可能带着超限的内联文本,这里统一按策略重新拆分。
    nonisolated static func normalizedStoredText(
        from incomingRecord: ClipboardRecordExport
    ) -> ClipboardTextSyncPolicy.StoredText? {
        guard let inlineText = incomingRecord.plainText else {
            guard let fullTextData = incomingRecord.fullTextData else { return nil }
            return ClipboardTextSyncPolicy.storedTextUsingPreferences(
                for: String(data: fullTextData, encoding: .utf8)
            )
        }

        if incomingRecord.fullTextData != nil {
            return ClipboardTextSyncPolicy.StoredText(
                inlineText: inlineText,
                fullTextData: incomingRecord.fullTextData,
                isTruncated: incomingRecord.isPlainTextTruncated
            )
        }

        if inlineText.utf8.count > ClipboardTextSyncPolicy.inlineLimitBytes {
            return ClipboardTextSyncPolicy.storedTextUsingPreferences(for: inlineText)
        }

        return ClipboardTextSyncPolicy.StoredText(
            inlineText: inlineText,
            fullTextData: nil,
            isTruncated: incomingRecord.isPlainTextTruncated
        )
    }

    func merge(_ source: ClipboardRecord, into target: ClipboardRecord) {
        let sourceIsNewer = source.timestamp > target.timestamp

        target.timestamp = max(target.timestamp, source.timestamp)
        target.isPinned = target.isPinned || source.isPinned

        if sourceIsNewer {
            target.typeRawValue = source.typeRawValue
            target.sourcePlatformRawValue = source.sourcePlatformRawValue
            target.sourceDeviceName = source.sourceDeviceName ?? target.sourceDeviceName
            target.captureMethodRawValue = source.captureMethodRawValue
            target.captureSessionID = source.captureSessionID ?? target.captureSessionID
        }

        if target.plainText == nil, source.plainText != nil {
            // 文本三元组(内联前缀/全文/截断标记)必须整体迁移,拆开取值会破坏一致性。
            target.plainText = source.plainText
            target.fullTextData = source.fullTextData
            target.isPlainTextTruncated = source.isPlainTextTruncated
        } else if target.fullTextData == nil, let sourceFullTextData = source.fullTextData {
            // 同 contentHash 意味着同一份原文;副本带有全文时借此补全(并解除截断标记)。
            target.fullTextData = sourceFullTextData
            target.isPlainTextTruncated = false
        }
        target.previewImageData = target.previewImageData ?? source.previewImageData
        target.imageData = target.imageData ?? source.imageData
        target.imageUTType = target.imageUTType ?? source.imageUTType
        target.imageByteCount = target.imageByteCount ?? source.imageByteCount
        target.imagePixelWidth = target.imagePixelWidth ?? source.imagePixelWidth
        target.imagePixelHeight = target.imagePixelHeight ?? source.imagePixelHeight
        target.appBundleID = target.appBundleID ?? source.appBundleID
        target.appLocalizedName = target.appLocalizedName ?? source.appLocalizedName
        target.appIconDominantColorHex = target.appIconDominantColorHex ?? source.appIconDominantColorHex
        target.appIconData = target.appIconData ?? source.appIconData
        target.customTitle = target.customTitle ?? source.customTitle
        target.linkTitle = target.linkTitle ?? source.linkTitle
        target.linkIconData = target.linkIconData ?? source.linkIconData
        target.rtfData = target.rtfData ?? source.rtfData
        target.richTextArchiveData = target.richTextArchiveData ?? source.richTextArchiveData

        var mergedGroupIDs = normalizedGroupIDs(
            primaryGroupID: target.groupId,
            groupIdsRaw: target.groupIdsRaw
        )
        let sourceGroupIDs = normalizedGroupIDs(
            primaryGroupID: source.groupId,
            groupIdsRaw: source.groupIdsRaw
        )

        for groupID in sourceGroupIDs where mergedGroupIDs.contains(groupID) == false {
            mergedGroupIDs.append(groupID)
        }

        target.groupId = mergedGroupIDs.first
        target.groupIdsRaw = encodedGroupIDs(mergedGroupIDs)
    }

    func shouldPreferSurvivor(_ lhs: ClipboardRecord, over rhs: ClipboardRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }

        return lhs.id.uuidString.localizedStandardCompare(rhs.id.uuidString) == .orderedAscending
    }

    func refreshStoredTextRepresentations(
        for record: ClipboardRecord,
        type: String,
        rtfData: Data?,
        richTextArchiveData: Data?
    ) {
        let shouldRetainTextRepresentations = type != ClipboardContentType.image.rawValue
            && type != ClipboardContentType.fileURL.rawValue

        guard shouldRetainTextRepresentations else {
            record.rtfData = nil
            record.richTextArchiveData = nil
            return
        }

        record.rtfData = rtfData
        record.richTextArchiveData = richTextArchiveData
            ?? rtfData.flatMap { ClipboardRichTextArchive.fromRTFData($0)?.encodedData() }
    }

    func fetchStoredRecord(id: UUID) -> ClipboardRecord? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in record.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchStoredRecord(hash: String) -> ClipboardRecord? {
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchStoredGroup(id: String) -> ClipboardGroupModel? {
        var descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in group.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
