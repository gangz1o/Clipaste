import Foundation
import SwiftData

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

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentHash: String,
        typeRawValue: String,
        plainText: String? = nil,
        thumbnailPath: String? = nil,
        originalFilePath: String? = nil,
        appBundleID: String? = nil,
        appLocalizedName: String? = nil
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
    }
}
