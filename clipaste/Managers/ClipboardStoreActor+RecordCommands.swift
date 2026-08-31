import Foundation
import SwiftData

extension ClipboardStoreActor {
    func upsert(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        appIconDominantColorHex: String?,
        appIconData: Data?,
        type: String,
        rtfData: Data?,
        richTextArchiveData: Data?,
        previewImageData: Data?,
        imageData: Data?,
        imageMetadata: ClipboardImageMetadata?,
        sourcePlatformRawValue: String,
        sourceDeviceName: String?,
        captureMethodRawValue: String,
        captureSessionID: UUID?
    ) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )

        do {
            let now = Date()

            let existingRecords = try modelContext.fetch(descriptor)

            if let existingRecord = existingRecords.sorted(by: shouldPreferSurvivor).first {
                existingRecord.timestamp = now
                existingRecord.typeRawValue = type
                existingRecord.appBundleID = appID
                existingRecord.appLocalizedName = appName
                existingRecord.appIconDominantColorHex = appIconDominantColorHex
                if let appIconData {
                    existingRecord.appIconData = appIconData
                }
                existingRecord.sourcePlatformRawValue = sourcePlatformRawValue
                existingRecord.sourceDeviceName = sourceDeviceName
                existingRecord.captureMethodRawValue = captureMethodRawValue
                existingRecord.captureSessionID = captureSessionID

                if let text {
                    let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: text)
                    existingRecord.plainText = storedText.inlineText
                    existingRecord.fullTextData = storedText.fullTextData
                    existingRecord.isPlainTextTruncated = storedText.isTruncated
                } else if type != ClipboardContentType.image.rawValue {
                    existingRecord.plainText = nil
                    existingRecord.fullTextData = nil
                    existingRecord.isPlainTextTruncated = false
                }

                refreshStoredTextRepresentations(
                    for: existingRecord,
                    type: type,
                    rtfData: rtfData,
                    richTextArchiveData: richTextArchiveData
                )

                if let previewImageData {
                    existingRecord.previewImageData = previewImageData
                }

                if let imageData {
                    existingRecord.imageData = imageData
                }

                if let imageMetadata {
                    existingRecord.imageUTType = imageMetadata.utTypeIdentifier
                    existingRecord.imageByteCount = imageMetadata.byteCount
                    existingRecord.imagePixelWidth = imageMetadata.pixelWidth
                    existingRecord.imagePixelHeight = imageMetadata.pixelHeight
                }

                for duplicate in existingRecords where duplicate.id != existingRecord.id {
                    merge(duplicate, into: existingRecord)
                    modelContext.delete(duplicate)
                }
            } else {
                let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: text)
                let newRecord = ClipboardRecord(
                    timestamp: now,
                    contentHash: hash,
                    typeRawValue: type,
                    plainText: storedText.inlineText,
                    fullTextData: storedText.fullTextData,
                    isPlainTextTruncated: storedText.isTruncated,
                    previewImageData: previewImageData,
                    imageData: imageData,
                    imageMetadata: imageMetadata,
                    appBundleID: appID,
                    appLocalizedName: appName,
                    appIconDominantColorHex: appIconDominantColorHex,
                    appIconData: appIconData,
                    rtfData: rtfData,
                    richTextArchiveData: richTextArchiveData,
                    sourcePlatformRawValue: sourcePlatformRawValue,
                    sourceDeviceName: sourceDeviceName,
                    captureMethodRawValue: captureMethodRawValue,
                    captureSessionID: captureSessionID
                )
                modelContext.insert(newRecord)
            }

            try markSyncAnchorUpdated()
            try modelContext.save()
            NotificationCenter.default.post(
                name: .clipboardRecordDidChange,
                object: nil,
                userInfo: [
                    "contentHash": hash,
                    "kind": ClipboardRecordChangeKind.upsert.rawValue
                ]
            )
        } catch {
            print("❌ [ClipboardStoreActor] 写入失败: \(error)")
        }
    }

    func cleanUpExpiredRecords(before expirationDate: Date) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.timestamp < expirationDate }
        )

        do {
            let expiredRecords = try modelContext.fetch(descriptor)
            guard !expiredRecords.isEmpty else { return }

            for record in expiredRecords {
                modelContext.delete(record)
            }

            try markSyncAnchorUpdated()
            try modelContext.save()
        } catch {
            print("❌ [清理任务] 清理过期记录失败: \(error)")
        }
    }

    func delete(hash: String) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        do {
            if let recordToDelete = try modelContext.fetch(descriptor).first {
                modelContext.delete(recordToDelete)
                try markSyncAnchorUpdated()
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.delete.rawValue
                    ]
                )
            }
        } catch {
            print("❌ [ClipboardStoreActor] 删除失败: \(error)")
        }
    }

    func deleteUnpinnedRecords() {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.isPinned == false }
        )
        do {
            let records = try modelContext.fetch(descriptor)
            guard !records.isEmpty else { return }

            for record in records {
                modelContext.delete(record)
            }

            try markSyncAnchorUpdated()
            try modelContext.save()
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        } catch {
            print("❌ [ClipboardStoreActor] 清空失败: \(error)")
        }
    }
}
