import Foundation
import SwiftData

struct ClipboardRecordExport: Sendable {
    let id: UUID
    let timestamp: Date
    let contentHash: String
    let typeRawValue: String
    let plainText: String?
    let previewImageData: Data?
    let imageData: Data?
    let imageUTType: String?
    let imageByteCount: Int?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let appBundleID: String?
    let appLocalizedName: String?
    let appIconDominantColorHex: String?
    let groupId: String?
    let groupIdsRaw: String?
    let customTitle: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let rtfData: Data?
    let richTextArchiveData: Data?
}

struct ClipboardGroupExport: Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let systemIconName: String?
    let sortOrder: Int
}

struct ClipboardStoreExport: Sendable {
    let records: [ClipboardRecordExport]
    let groups: [ClipboardGroupExport]
}

enum ClipboardLegacySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ClipboardRecord.self, ClipboardGroupModel.self]
    }

    @Model
    final class ClipboardRecord {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var contentHash: String
        var typeRawValue: String
        var plainText: String?
        var thumbnailPath: String?
        var originalFilePath: String?
        var appBundleID: String?
        var appLocalizedName: String?
        var groupId: String?
        var groupIdsRaw: String?
        var customTitle: String?
        var linkTitle: String?
        var linkIconData: Data?
        var isPinned: Bool
        var rtfData: Data?

        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            contentHash: String,
            typeRawValue: String,
            plainText: String? = nil,
            thumbnailPath: String? = nil,
            originalFilePath: String? = nil,
            appBundleID: String? = nil,
            appLocalizedName: String? = nil,
            groupId: String? = nil,
            groupIdsRaw: String? = nil,
            customTitle: String? = nil,
            linkTitle: String? = nil,
            linkIconData: Data? = nil,
            isPinned: Bool = false,
            rtfData: Data? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.contentHash = contentHash
            self.typeRawValue = typeRawValue
            self.plainText = plainText
            self.thumbnailPath = thumbnailPath
            self.originalFilePath = originalFilePath
            self.appBundleID = appBundleID
            self.appLocalizedName = appLocalizedName
            self.groupId = groupId
            self.groupIdsRaw = groupIdsRaw
            self.customTitle = customTitle
            self.linkTitle = linkTitle
            self.linkIconData = linkIconData
            self.isPinned = isPinned
            self.rtfData = rtfData
        }
    }

    @Model
    final class ClipboardGroupModel {
        @Attribute(.unique) var id: String
        var name: String
        var createdAt: Date
        var systemIconName: String
        var sortOrder: Int

        init(
            id: String = UUID().uuidString,
            name: String,
            createdAt: Date = Date(),
            systemIconName: String = "folder",
            sortOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.systemIconName = systemIconName
            self.sortOrder = sortOrder
        }
    }
}

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
        let legacyRecords = try context.fetch(
            FetchDescriptor<ClipboardLegacySchemaV1.ClipboardRecord>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )

        guard legacyGroups.isEmpty == false || legacyRecords.isEmpty == false else {
            defaults.set(true, forKey: Keys.legacyImportCompleted)
            return
        }

        let payload = ClipboardStoreExport(
            records: legacyRecords.compactMap(Self.makeLegacyRecordExport(from:)),
            groups: legacyGroups.map(Self.makeLegacyGroupExport(from:))
        )

        try await target.importStoreExport(payload)
        defaults.set(true, forKey: Keys.legacyImportCompleted)
    }

    func merge(from source: StorageManager, to target: StorageManager) async throws {
        let payload = await source.exportStore()
        try await target.importStoreExport(payload)
    }

    private static func makeLegacyGroupExport(
        from group: ClipboardLegacySchemaV1.ClipboardGroupModel
    ) -> ClipboardGroupExport {
        ClipboardGroupExport(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            systemIconName: ClipboardGroupIconName.normalize(group.systemIconName),
            sortOrder: group.sortOrder
        )
    }

    private static func makeLegacyRecordExport(
        from record: ClipboardLegacySchemaV1.ClipboardRecord
    ) -> ClipboardRecordExport? {
        let imageBinary = makeLegacyImageBinary(
            typeRawValue: record.typeRawValue,
            originalFilePath: record.originalFilePath,
            thumbnailPath: record.thumbnailPath
        )

        return ClipboardRecordExport(
            id: record.id,
            timestamp: record.timestamp,
            contentHash: record.contentHash,
            typeRawValue: record.typeRawValue,
            plainText: record.plainText,
            previewImageData: imageBinary?.previewData,
            imageData: imageBinary?.fullData,
            imageUTType: imageBinary?.metadata.utTypeIdentifier,
            imageByteCount: imageBinary?.metadata.byteCount,
            imagePixelWidth: imageBinary?.metadata.pixelWidth,
            imagePixelHeight: imageBinary?.metadata.pixelHeight,
            appBundleID: record.appBundleID,
            appLocalizedName: record.appLocalizedName,
            appIconDominantColorHex: nil,
            groupId: record.groupId,
            groupIdsRaw: record.groupIdsRaw,
            customTitle: nil,
            linkTitle: record.linkTitle,
            linkIconData: record.linkIconData,
            isPinned: record.isPinned,
            rtfData: record.rtfData,
            richTextArchiveData: nil
        )
    }

    private static func makeLegacyImageBinary(
        typeRawValue: String,
        originalFilePath: String?,
        thumbnailPath: String?
    ) -> LegacyImageBinary? {
        guard typeRawValue == ClipboardContentType.image.rawValue else { return nil }

        let fullURL = resolveLegacyURL(relativePath: originalFilePath)
        let previewURL = resolveLegacyURL(relativePath: thumbnailPath)

        let fullData = fullURL.flatMap { try? Data(contentsOf: $0) }
            ?? previewURL.flatMap { try? Data(contentsOf: $0) }
        guard let fullData else { return nil }

        let previewData = previewURL.flatMap { try? Data(contentsOf: $0) }
            ?? ImageProcessor.generateThumbnail(
                from: fullData,
                maxPixelSize: ClipboardImagePreviewPolicy.storedPreviewMaxPixelSize
            )
        let metadata = ImageProcessor.metadata(for: fullData)

        return LegacyImageBinary(fullData: fullData, previewData: previewData, metadata: metadata)
    }

    private static func resolveLegacyURL(relativePath: String?) -> URL? {
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

private struct LegacyImageBinary {
    let fullData: Data
    let previewData: Data?
    let metadata: ClipboardImageMetadata
}

private extension ClipboardStoreBootstrapper {
    enum Keys {
        static let legacyImportCompleted = "clipboard_legacy_import_completed_v2"
    }
}
