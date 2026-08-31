import Foundation
import SwiftData

nonisolated enum ClipboardStoreExportPolicy {
    static let maximumBatchPayloadByteCount = 96 * 1_024 * 1_024
}

enum ClipboardStoreExportError: LocalizedError {
    case recordPayloadExceedsLimit(limit: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .recordPayloadExceedsLimit(limit, actual):
            return "A clipboard record payload (\(actual) bytes) exceeds the transfer limit (\(limit) bytes)."
        }
    }
}

struct ClipboardRecordExport: Sendable {
    let id: UUID
    let timestamp: Date
    let contentHash: String
    let typeRawValue: String
    let plainText: String?
    let fullTextData: Data?
    let isPlainTextTruncated: Bool
    let previewImageData: Data?
    let imageData: Data?
    let imageUTType: String?
    let imageByteCount: Int?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let appBundleID: String?
    let appLocalizedName: String?
    let appIconDominantColorHex: String?
    let appIconData: Data?
    let groupId: String?
    let groupIdsRaw: String?
    let customTitle: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let rtfData: Data?
    let richTextArchiveData: Data?
    let sourcePlatformRawValue: String
    let sourceDeviceName: String?
    let captureMethodRawValue: String
    let captureSessionID: UUID?
}

extension ClipboardRecordExport {
    nonisolated var estimatedPayloadByteCount: Int {
        let dataFields = [
            fullTextData,
            previewImageData,
            imageData,
            appIconData,
            linkIconData,
            rtfData,
            richTextArchiveData
        ]
        let stringFields = [
            contentHash,
            typeRawValue,
            plainText,
            imageUTType,
            appBundleID,
            appLocalizedName,
            appIconDominantColorHex,
            groupId,
            groupIdsRaw,
            customTitle,
            linkTitle,
            sourcePlatformRawValue,
            sourceDeviceName,
            captureMethodRawValue
        ]

        let dataByteCount = dataFields.reduce(0) {
            saturatingClipboardPayloadAdd($0, $1?.count ?? 0)
        }
        let stringByteCount = stringFields.reduce(0) {
            saturatingClipboardPayloadAdd($0, $1?.utf8.count ?? 0)
        }
        return saturatingClipboardPayloadAdd(dataByteCount, stringByteCount)
    }

    nonisolated func validatedPayloadByteCount() throws -> Int {
        let actualByteCount = estimatedPayloadByteCount
        let limit = ClipboardStoreExportPolicy.maximumBatchPayloadByteCount
        guard actualByteCount <= limit else {
            throw ClipboardStoreExportError.recordPayloadExceedsLimit(
                limit: limit,
                actual: actualByteCount
            )
        }
        return actualByteCount
    }
}

nonisolated private func saturatingClipboardPayloadAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
}

struct ClipboardGroupExport: Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let systemIconName: String?
    let sortOrder: Int
    let deletedAt: Date?
    let deletedByDevice: String
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
