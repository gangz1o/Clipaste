import Foundation
import SwiftData


nonisolated struct ClipboardRecordSnapshot: Sendable {
    let id: UUID
    let contentHash: String
    let bundleIdentifier: String?
    let appName: String
    let appIconDominantColorHex: String?
    let timestamp: Date
    let plainText: String?
    let hasPreviewImage: Bool
    let hasImageData: Bool
    let imageUTType: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let typeRawValue: String
    let groupId: String?
    let groupIdsRaw: String?
    let customTitle: String?
    let linkTitle: String?
    let linkIconData: Data?
    let isPinned: Bool
    let hasRTF: Bool
    let sourcePlatformRawValue: String
    let sourceDeviceName: String?
    let captureMethodRawValue: String
    let captureSessionID: UUID?

    /// Build a snapshot without touching any `@Attribute(.externalStorage)`
    /// property on the record. External-storage getters trap with EXC_BAD_ACCESS
    /// when the backing file has been removed by a concurrent write on another
    /// `@ModelActor` — a hard-to-recover crash we hit when the user mashes
    /// delete while a search/page fetch is in flight. We derive the
    /// "has-X" hints from regular columns instead and let downstream loaders
    /// (which hit the store actor with a fresh fetch) handle the actual blobs.
    static func makeFromRecord(_ record: ClipboardRecord) -> ClipboardRecordSnapshot {
        let truncatedText: String? = {
            guard let text = record.plainText else { return nil }
            return text.count > 500 ? String(text.prefix(500)) : text
        }()

        let isImageType = record.typeRawValue == ClipboardContentType.image.rawValue
        let mayHaveRichText: Bool = {
            switch record.typeRawValue {
            case ClipboardContentType.text.rawValue,
                 ClipboardContentType.code.rawValue:
                return true
            default:
                return false
            }
        }()

        return ClipboardRecordSnapshot(
            id: record.id,
            contentHash: record.contentHash,
            bundleIdentifier: record.appBundleID,
            appName: record.appLocalizedName ?? "Unknown App",
            appIconDominantColorHex: record.appIconDominantColorHex,
            timestamp: record.timestamp,
            plainText: truncatedText,
            hasPreviewImage: isImageType,
            hasImageData: isImageType,
            imageUTType: record.imageUTType,
            imagePixelWidth: record.imagePixelWidth,
            imagePixelHeight: record.imagePixelHeight,
            typeRawValue: record.typeRawValue,
            groupId: record.groupId,
            groupIdsRaw: record.groupIdsRaw,
            customTitle: record.customTitle,
            linkTitle: record.linkTitle,
            linkIconData: nil,
            isPinned: record.isPinned,
            hasRTF: mayHaveRichText,
            sourcePlatformRawValue: record.sourcePlatformRawValue,
            sourceDeviceName: record.sourceDeviceName,
            captureMethodRawValue: record.captureMethodRawValue,
            captureSessionID: record.captureSessionID
        )
    }
}

nonisolated struct LinkMetadataFailureState: Sendable {
    static let maximumAttemptCount = 3
    static let maximumTrackedHashCount = 256

    let attemptCount: Int
    let nextAllowedDate: Date
}

struct ClipboardStoreDiagnosticsSnapshot: Sendable {
    let recordCount: Int
    let groupCount: Int
    let latestRecordFingerprints: [String]
}

struct ClipboardPasteRecord: Sendable {
    let id: UUID
    let typeRawValue: String
    let plainText: String?
    let rtfData: Data?
    let richTextArchiveData: Data?
}

nonisolated func normalizedGroupIDs(primaryGroupID: String?, groupIdsRaw: String?) -> [String] {
    var result: [String] = []

    if let primaryGroupID, !primaryGroupID.isEmpty {
        result.append(primaryGroupID)
    }

    if let groupIdsRaw,
       let data = groupIdsRaw.data(using: .utf8),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
        for id in decoded where !id.isEmpty && result.contains(id) == false {
            result.append(id)
        }
    }

    return result
}

nonisolated func encodedGroupIDs(_ groupIDs: [String]) -> String? {
    let cleaned = groupIDs.reduce(into: [String]()) { result, id in
        guard !id.isEmpty, result.contains(id) == false else { return }
        result.append(id)
    }

    guard !cleaned.isEmpty,
          let data = try? JSONEncoder().encode(cleaned),
          let raw = String(data: data, encoding: .utf8) else {
        return nil
    }

    return raw
}
