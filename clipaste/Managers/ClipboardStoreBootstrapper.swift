import Foundation
import SwiftData

final class ClipboardStoreBootstrapper: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func importLegacyStoreIfNeeded(into target: StorageManager) async throws {
        guard defaults.bool(forKey: Keys.legacyImportCompleted) == false else { return }
        guard Self.hasLegacyStoreArtifacts else {
            defaults.set(true, forKey: Keys.legacyImportCompleted)
            return
        }

        let schema = Schema(versionedSchema: ClipboardLegacySchemaV1.self)
        let configuration = ModelConfiguration(
            "ClipboardLegacyStore",
            schema: schema,
            url: Self.legacyStoreURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let legacyGroups = try context.fetch(
            FetchDescriptor<ClipboardLegacySchemaV1.ClipboardGroupModel>(
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
        )
        if legacyGroups.isEmpty == false {
            try await target.importStoreExport(
                ClipboardStoreExport(
                    records: [],
                    groups: legacyGroups.map(Self.makeLegacyGroupExport(from:))
                )
            )
        }

        let batchSize = 128
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<ClipboardLegacySchemaV1.ClipboardRecord>(
                sortBy: [
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .forward)
                ]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let records = try context.fetch(descriptor)
            guard records.isEmpty == false else { break }

            var exports: [ClipboardRecordExport] = []
            exports.reserveCapacity(records.count)
            var payloadByteCount = 0
            for record in records {
                if let export = await Self.makeLegacyRecordExport(from: record) {
                    let recordByteCount = try export.validatedPayloadByteCount()
                    if exports.isEmpty == false,
                       payloadByteCount > ClipboardStoreExportPolicy.maximumBatchPayloadByteCount - recordByteCount {
                        try await target.importStoreExport(
                            ClipboardStoreExport(records: exports, groups: [])
                        )
                        exports.removeAll(keepingCapacity: true)
                        payloadByteCount = 0
                    }
                    exports.append(export)
                    payloadByteCount += recordByteCount
                }
            }
            if exports.isEmpty == false {
                try await target.importStoreExport(
                    ClipboardStoreExport(records: exports, groups: [])
                )
            }

            offset += records.count
            guard records.count == batchSize else { break }
            await Task.yield()
        }

        defaults.set(true, forKey: Keys.legacyImportCompleted)
    }

    func merge(from source: StorageManager, to target: StorageManager) async throws {
        let groups = try await source.exportGroups()
        try await target.importStoreExport(ClipboardStoreExport(records: [], groups: groups))

        let batchSize = 128
        _ = try await BoundedBatchTransfer.run(
            batchSize: batchSize,
            loadBatch: { offset, limit in
                try await source.exportRecordBatch(offset: offset, limit: limit)
            },
            consumeBatch: { records in
                try await target.importStoreExport(ClipboardStoreExport(records: records, groups: []))
            }
        )
    }

    private static func makeLegacyGroupExport(
        from group: ClipboardLegacySchemaV1.ClipboardGroupModel
    ) -> ClipboardGroupExport {
        ClipboardGroupExport(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            systemIconName: ClipboardGroupIconName.normalize(group.systemIconName),
            sortOrder: group.sortOrder,
            deletedAt: nil,
            deletedByDevice: ""
        )
    }

    private static func makeLegacyRecordExport(
        from record: ClipboardLegacySchemaV1.ClipboardRecord
    ) async -> ClipboardRecordExport? {
        let id = record.id
        let timestamp = record.timestamp
        let contentHash = record.contentHash
        let typeRawValue = record.typeRawValue
        let plainText = record.plainText
        let originalFilePath = record.originalFilePath
        let thumbnailPath = record.thumbnailPath
        let appBundleID = record.appBundleID
        let appLocalizedName = record.appLocalizedName
        let groupId = record.groupId
        let groupIdsRaw = record.groupIdsRaw
        let linkTitle = record.linkTitle
        let linkIconData = record.linkIconData
        let isPinned = record.isPinned
        let rtfData = record.rtfData

        let imageBinary = await Task.detached(priority: .utility) {
            makeLegacyImageBinary(
                typeRawValue: typeRawValue,
                originalFilePath: originalFilePath,
                thumbnailPath: thumbnailPath
            )
        }.value

        // 旧库文本可能超过 CloudKit 内联上限,导入时先按策略拆分,
        // 避免超大 plainText 直接进入云存储卡死导出队列。
        let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: plainText)

        return ClipboardRecordExport(
            id: id,
            timestamp: timestamp,
            contentHash: contentHash,
            typeRawValue: typeRawValue,
            plainText: storedText.inlineText,
            fullTextData: storedText.fullTextData,
            isPlainTextTruncated: storedText.isTruncated,
            previewImageData: imageBinary?.previewData,
            imageData: imageBinary?.fullData,
            imageUTType: imageBinary?.metadata.utTypeIdentifier,
            imageByteCount: imageBinary?.metadata.byteCount,
            imagePixelWidth: imageBinary?.metadata.pixelWidth,
            imagePixelHeight: imageBinary?.metadata.pixelHeight,
            appBundleID: appBundleID,
            appLocalizedName: appLocalizedName,
            appIconDominantColorHex: nil,
            appIconData: nil,
            groupId: groupId,
            groupIdsRaw: groupIdsRaw,
            customTitle: nil,
            linkTitle: linkTitle,
            linkIconData: linkIconData,
            isPinned: isPinned,
            rtfData: rtfData,
            richTextArchiveData: nil,
            sourcePlatformRawValue: ClipboardSourceMetadata.currentPlatform,
            sourceDeviceName: nil,
            captureMethodRawValue: ClipboardSourceMetadata.importedMethod,
            captureSessionID: nil
        )
    }

    nonisolated private static func makeLegacyImageBinary(
        typeRawValue: String,
        originalFilePath: String?,
        thumbnailPath: String?
    ) -> LegacyImageBinary? {
        guard typeRawValue == ClipboardContentType.image.rawValue else { return nil }

        let fullURL = resolveLegacyURL(relativePath: originalFilePath)
        let previewURL = resolveLegacyURL(relativePath: thumbnailPath)

        let fullData = fullURL.flatMap {
            ClipboardFileReference.accessibleData(
                from: $0,
                maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
            )
        } ?? previewURL.flatMap {
            ClipboardFileReference.accessibleData(
                from: $0,
                maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
            )
        }
        guard let fullData else { return nil }

        let metadata = ImageProcessor.metadata(for: fullData)
        guard ClipboardImageResourcePolicy.allowsStoredImage(metadata) else { return nil }

        let previewData = previewURL.flatMap {
            ClipboardFileReference.accessibleData(
                from: $0,
                maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
            )
        }
            ?? ImageProcessor.generateThumbnail(
                from: fullData,
                maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
            )

        return LegacyImageBinary(fullData: fullData, previewData: previewData, metadata: metadata)
    }

    nonisolated private static func resolveLegacyURL(relativePath: String?) -> URL? {
        guard let relativePath, relativePath.isEmpty == false else { return nil }

        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }

        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "clipaste"
        return applicationSupportURL?
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
    }

    private static var legacyStoreURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL.appendingPathComponent("default.store", isDirectory: false)
    }

    private static var hasLegacyStoreArtifacts: Bool {
        let fileManager = FileManager.default
        let directoryURL = legacyStoreURL.deletingLastPathComponent()
        let storePrefix = legacyStoreURL.lastPathComponent

        guard let candidateURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return candidateURLs.contains { $0.lastPathComponent.hasPrefix(storePrefix) }
    }
}

private nonisolated struct LegacyImageBinary: Sendable {
    let fullData: Data
    let previewData: Data?
    let metadata: ClipboardImageMetadata
}

private extension ClipboardStoreBootstrapper {
    enum Keys {
        static let legacyImportCompleted = "clipboard_legacy_import_completed_v2"
    }
}
