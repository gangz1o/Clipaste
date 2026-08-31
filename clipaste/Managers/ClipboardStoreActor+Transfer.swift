import Foundation
import SwiftData

extension ClipboardStoreActor {
    func exportGroups() throws -> [ClipboardGroupExport] {
        try modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())
            .map(Self.makeGroupExport(from:))
    }

    func exportRecordBatch(offset: Int, limit: Int) throws -> [ClipboardRecordExport] {
        guard offset >= 0, limit > 0 else { return [] }

        var descriptor = FetchDescriptor<ClipboardRecord>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let records = try modelContext.fetch(descriptor)
        return try Self.makeBoundedRecordExports(from: records)
    }

    func exportPinnedRecordBatch(offset: Int, limit: Int) throws -> ClipboardStoreExport {
        guard offset >= 0, limit > 0 else {
            return ClipboardStoreExport(records: [], groups: [])
        }

        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { $0.isPinned },
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let records = try Self.makeBoundedRecordExports(from: modelContext.fetch(descriptor))
        let referencedGroupIDs = Set(
            records.flatMap {
                normalizedGroupIDs(primaryGroupID: $0.groupId, groupIdsRaw: $0.groupIdsRaw)
            }
        )
        let groups = try modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())
            .filter { referencedGroupIDs.contains($0.id) }
            .map(Self.makeGroupExport(from:))

        return ClipboardStoreExport(records: records, groups: groups)
    }

    private static func makeBoundedRecordExports(
        from records: [ClipboardRecord]
    ) throws -> [ClipboardRecordExport] {
        var exports: [ClipboardRecordExport] = []
        exports.reserveCapacity(records.count)
        var payloadByteCount = 0

        for record in records {
            let export = Self.makeRecordExport(from: record)
            let recordByteCount = try export.validatedPayloadByteCount()
            if exports.isEmpty == false,
               payloadByteCount > ClipboardStoreExportPolicy.maximumBatchPayloadByteCount - recordByteCount {
                break
            }

            exports.append(export)
            payloadByteCount += recordByteCount
        }

        return exports
    }

    func importStoreExport(_ payload: ClipboardStoreExport) throws {
        var groupsByID: [String: ClipboardGroupModel] = [:]
        groupsByID.reserveCapacity(payload.groups.count)

        for incomingGroup in payload.groups {
            if let existingGroup = groupsByID[incomingGroup.id] ?? fetchStoredGroup(id: incomingGroup.id) {
                groupsByID[incomingGroup.id] = existingGroup
                if let incomingDeletedAt = incomingGroup.deletedAt {
                    if existingGroup.deletedAt == nil || incomingDeletedAt > (existingGroup.deletedAt ?? .distantPast) {
                        existingGroup.deletedAt = incomingDeletedAt
                        existingGroup.deletedByDevice = incomingGroup.deletedByDevice
                    }
                } else if existingGroup.deletedAt == nil {
                    existingGroup.name = incomingGroup.name
                    existingGroup.systemIconName = ClipboardGroupIconName.storageValue(from: incomingGroup.systemIconName)
                    existingGroup.sortOrder = incomingGroup.sortOrder
                }
            } else {
                let group = ClipboardGroupModel(
                    id: incomingGroup.id,
                    name: incomingGroup.name,
                    systemIconName: incomingGroup.systemIconName,
                    sortOrder: incomingGroup.sortOrder,
                    deletedAt: incomingGroup.deletedAt,
                    deletedByDevice: incomingGroup.deletedByDevice
                )
                group.createdAt = incomingGroup.createdAt
                modelContext.insert(group)
                groupsByID[incomingGroup.id] = group
            }
        }

        var recordsByHash: [String: ClipboardRecord] = [:]
        recordsByHash.reserveCapacity(payload.records.count)

        for incomingRecord in payload.records {
            let incomingHash = incomingRecord.contentHash
            let existingRecord = recordsByHash[incomingHash] ?? fetchStoredRecord(hash: incomingHash)
            if let existingRecord {
                recordsByHash[incomingHash] = existingRecord
                existingRecord.timestamp = max(existingRecord.timestamp, incomingRecord.timestamp)
                existingRecord.typeRawValue = incomingRecord.typeRawValue
                existingRecord.appBundleID = incomingRecord.appBundleID ?? existingRecord.appBundleID
                existingRecord.appLocalizedName = incomingRecord.appLocalizedName ?? existingRecord.appLocalizedName
                existingRecord.appIconDominantColorHex = incomingRecord.appIconDominantColorHex ?? existingRecord.appIconDominantColorHex
                existingRecord.appIconData = incomingRecord.appIconData ?? existingRecord.appIconData
                if let incomingStoredText = Self.normalizedStoredText(from: incomingRecord) {
                    existingRecord.plainText = incomingStoredText.inlineText
                    existingRecord.fullTextData = incomingStoredText.fullTextData
                    existingRecord.isPlainTextTruncated = incomingStoredText.isTruncated
                }
                existingRecord.previewImageData = incomingRecord.previewImageData ?? existingRecord.previewImageData
                existingRecord.imageData = incomingRecord.imageData ?? existingRecord.imageData
                existingRecord.imageUTType = incomingRecord.imageUTType ?? existingRecord.imageUTType
                existingRecord.imageByteCount = incomingRecord.imageByteCount ?? existingRecord.imageByteCount
                existingRecord.imagePixelWidth = incomingRecord.imagePixelWidth ?? existingRecord.imagePixelWidth
                existingRecord.imagePixelHeight = incomingRecord.imagePixelHeight ?? existingRecord.imagePixelHeight
                existingRecord.customTitle = incomingRecord.customTitle ?? existingRecord.customTitle
                existingRecord.linkTitle = incomingRecord.linkTitle ?? existingRecord.linkTitle
                existingRecord.linkIconData = incomingRecord.linkIconData ?? existingRecord.linkIconData
                existingRecord.rtfData = incomingRecord.rtfData ?? existingRecord.rtfData
                existingRecord.richTextArchiveData = incomingRecord.richTextArchiveData ?? existingRecord.richTextArchiveData
                existingRecord.isPinned = existingRecord.isPinned || incomingRecord.isPinned
                existingRecord.sourcePlatformRawValue = incomingRecord.sourcePlatformRawValue
                existingRecord.sourceDeviceName = incomingRecord.sourceDeviceName ?? existingRecord.sourceDeviceName
                existingRecord.captureMethodRawValue = incomingRecord.captureMethodRawValue
                existingRecord.captureSessionID = incomingRecord.captureSessionID ?? existingRecord.captureSessionID

                var mergedGroupIDs = normalizedGroupIDs(
                    primaryGroupID: existingRecord.groupId,
                    groupIdsRaw: existingRecord.groupIdsRaw
                )
                let incomingGroupIDs = normalizedGroupIDs(
                    primaryGroupID: incomingRecord.groupId,
                    groupIdsRaw: incomingRecord.groupIdsRaw
                )
                for groupID in incomingGroupIDs where mergedGroupIDs.contains(groupID) == false {
                    mergedGroupIDs.append(groupID)
                }
                existingRecord.groupId = mergedGroupIDs.first
                existingRecord.groupIdsRaw = encodedGroupIDs(mergedGroupIDs)
            } else {
                let importedImageMetadata: ClipboardImageMetadata? = {
                    guard incomingRecord.imageData != nil
                            || incomingRecord.previewImageData != nil
                            || incomingRecord.imageUTType != nil
                            || incomingRecord.imageByteCount != nil
                            || incomingRecord.imagePixelWidth != nil
                            || incomingRecord.imagePixelHeight != nil else {
                        return nil
                    }

                    return ClipboardImageMetadata(
                        utTypeIdentifier: incomingRecord.imageUTType,
                        byteCount: incomingRecord.imageByteCount ?? incomingRecord.imageData?.count ?? 0,
                        pixelWidth: incomingRecord.imagePixelWidth,
                        pixelHeight: incomingRecord.imagePixelHeight
                    )
                }()

                let incomingStoredText = Self.normalizedStoredText(from: incomingRecord)
                let record = ClipboardRecord(
                    id: incomingRecord.id,
                    timestamp: incomingRecord.timestamp,
                    contentHash: incomingRecord.contentHash,
                    typeRawValue: incomingRecord.typeRawValue,
                    plainText: incomingStoredText?.inlineText,
                    fullTextData: incomingStoredText?.fullTextData,
                    isPlainTextTruncated: incomingStoredText?.isTruncated ?? false,
                    previewImageData: incomingRecord.previewImageData,
                    imageData: incomingRecord.imageData,
                    imageMetadata: importedImageMetadata,
                    appBundleID: incomingRecord.appBundleID,
                    appLocalizedName: incomingRecord.appLocalizedName,
                    appIconDominantColorHex: incomingRecord.appIconDominantColorHex,
                    appIconData: incomingRecord.appIconData,
                    groupId: incomingRecord.groupId,
                    groupIdsRaw: incomingRecord.groupIdsRaw,
                    customTitle: incomingRecord.customTitle,
                    linkTitle: incomingRecord.linkTitle,
                    linkIconData: incomingRecord.linkIconData,
                    isPinned: incomingRecord.isPinned,
                    rtfData: incomingRecord.rtfData,
                    richTextArchiveData: incomingRecord.richTextArchiveData,
                    sourcePlatformRawValue: incomingRecord.sourcePlatformRawValue,
                    sourceDeviceName: incomingRecord.sourceDeviceName,
                    captureMethodRawValue: incomingRecord.captureMethodRawValue,
                    captureSessionID: incomingRecord.captureSessionID
                )
                modelContext.insert(record)
                recordsByHash[incomingHash] = record
            }
        }

        try modelContext.save()
    }

    private nonisolated static func makeRecordExport(from record: ClipboardRecord) -> ClipboardRecordExport {
        ClipboardRecordExport(
            id: record.id,
            timestamp: record.timestamp,
            contentHash: record.contentHash,
            typeRawValue: record.typeRawValue,
            plainText: record.plainText,
            fullTextData: record.fullTextData,
            isPlainTextTruncated: record.isPlainTextTruncated,
            previewImageData: record.previewImageData,
            imageData: record.imageData,
            imageUTType: record.imageUTType,
            imageByteCount: record.imageByteCount,
            imagePixelWidth: record.imagePixelWidth,
            imagePixelHeight: record.imagePixelHeight,
            appBundleID: record.appBundleID,
            appLocalizedName: record.appLocalizedName,
            appIconDominantColorHex: record.appIconDominantColorHex,
            appIconData: record.appIconData,
            groupId: record.groupId,
            groupIdsRaw: record.groupIdsRaw,
            customTitle: record.customTitle,
            linkTitle: record.linkTitle,
            linkIconData: record.linkIconData,
            isPinned: record.isPinned,
            rtfData: record.rtfData,
            richTextArchiveData: record.richTextArchiveData,
            sourcePlatformRawValue: record.sourcePlatformRawValue,
            sourceDeviceName: record.sourceDeviceName,
            captureMethodRawValue: record.captureMethodRawValue,
            captureSessionID: record.captureSessionID
        )
    }

    private nonisolated static func makeGroupExport(from group: ClipboardGroupModel) -> ClipboardGroupExport {
        ClipboardGroupExport(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            systemIconName: group.resolvedSystemIconName,
            sortOrder: group.sortOrder,
            deletedAt: group.deletedAt,
            deletedByDevice: group.deletedByDevice
        )
    }
}
