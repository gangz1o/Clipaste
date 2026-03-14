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
    var groupId: String? // 所属分组 ID
    var linkTitle: String?     // 链接预览：网页标题
    var linkIconData: Data?    // 链接预览：网站图标数据
    var isPinned: Bool = false // 固定状态

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
        linkTitle: String? = nil,
        linkIconData: Data? = nil,
        isPinned: Bool = false
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
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
        self.isPinned = isPinned
    }
}
