import Foundation
import SwiftData

@Model
final class ClipboardRecord {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var contentHash: String = ""
    var typeRawValue: String = ClipboardContentType.text.rawValue
    var plainText: String?
    @Attribute(.externalStorage) var previewImageData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var imageUTType: String?
    var imageByteCount: Int?
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    var appBundleID: String?
    var appLocalizedName: String?
    var appIconDominantColorHex: String?
    var groupId: String? // 所属分组 ID
    var groupIdsRaw: String? // 多分组兼容存储(JSON)
    var customTitle: String? // 用户手动添加的标题
    var linkTitle: String? // 链接预览：网页标题
    @Attribute(.externalStorage) var linkIconData: Data? // 链接预览：网站图标数据
    var isPinned: Bool = false // 固定状态
    @Attribute(.externalStorage) var rtfData: Data? // 预览/编辑使用的 RTF（原始 RTF 或后台回退生成）
    @Attribute(.externalStorage) var richTextArchiveData: Data? // 原始富格式集合（HTML/RTF/RTFD/Tabular Text）

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentHash: String,
        typeRawValue: String,
        plainText: String? = nil,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil,
        appBundleID: String? = nil,
        appLocalizedName: String? = nil,
        appIconDominantColorHex: String? = nil,
        groupId: String? = nil,
        groupIdsRaw: String? = nil,
        customTitle: String? = nil,
        linkTitle: String? = nil,
        linkIconData: Data? = nil,
        isPinned: Bool = false,
        rtfData: Data? = nil,
        richTextArchiveData: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.typeRawValue = typeRawValue
        self.plainText = plainText
        self.previewImageData = previewImageData
        self.imageData = imageData
        self.imageUTType = imageMetadata?.utTypeIdentifier
        self.imageByteCount = imageMetadata?.byteCount
        self.imagePixelWidth = imageMetadata?.pixelWidth
        self.imagePixelHeight = imageMetadata?.pixelHeight
        self.appBundleID = appBundleID
        self.appLocalizedName = appLocalizedName
        self.appIconDominantColorHex = appIconDominantColorHex
        self.groupId = groupId
        self.groupIdsRaw = groupIdsRaw
        self.customTitle = customTitle
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
        self.isPinned = isPinned
        self.rtfData = rtfData
        self.richTextArchiveData = richTextArchiveData
    }
}
