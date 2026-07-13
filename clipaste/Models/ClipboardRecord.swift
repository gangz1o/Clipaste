import Foundation
import SwiftData

@Model
final class ClipboardRecord {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var contentHash: String = ""
    var typeRawValue: String = ClipboardContentType.text.rawValue
    var plainText: String?
    /// 超大文本的完整 UTF-8 数据。CloudKit 内联字段有 1MB 硬上限,超过
    /// `ClipboardTextSyncPolicy.inlineLimitBytes` 的文本全文存这里(同步走
    /// CKAsset),`plainText` 只保留截断前缀供搜索/预览。
    @Attribute(.externalStorage) var fullTextData: Data?
    /// 文本超过用户设置的同步大小上限、超出部分未保留时为 true。
    var isPlainTextTruncated: Bool = false
    @Attribute(.externalStorage) var previewImageData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var imageUTType: String?
    var imageByteCount: Int?
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    var appBundleID: String?
    var appLocalizedName: String?
    var appIconDominantColorHex: String?
    @Attribute(.externalStorage) var appIconData: Data?
    var groupId: String? // 所属分组 ID
    var groupIdsRaw: String? // 多分组兼容存储(JSON)
    var customTitle: String? // 用户手动添加的标题
    var linkTitle: String? // 链接预览：网页标题
    @Attribute(.externalStorage) var linkIconData: Data? // 链接预览：网站图标数据
    var isPinned: Bool = false // 固定状态
    @Attribute(.externalStorage) var rtfData: Data? // 预览/编辑使用的 RTF（原始 RTF 或后台回退生成）
    @Attribute(.externalStorage) var richTextArchiveData: Data? // 原始富格式集合（HTML/RTF/RTFD/Tabular Text）
    var sourcePlatformRawValue: String = "macOS"
    var sourceDeviceName: String?
    var captureMethodRawValue: String = "monitor"
    var captureSessionID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentHash: String,
        typeRawValue: String,
        plainText: String? = nil,
        fullTextData: Data? = nil,
        isPlainTextTruncated: Bool = false,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil,
        appBundleID: String? = nil,
        appLocalizedName: String? = nil,
        appIconDominantColorHex: String? = nil,
        appIconData: Data? = nil,
        groupId: String? = nil,
        groupIdsRaw: String? = nil,
        customTitle: String? = nil,
        linkTitle: String? = nil,
        linkIconData: Data? = nil,
        isPinned: Bool = false,
        rtfData: Data? = nil,
        richTextArchiveData: Data? = nil,
        sourcePlatformRawValue: String = "macOS",
        sourceDeviceName: String? = nil,
        captureMethodRawValue: String = "monitor",
        captureSessionID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.typeRawValue = typeRawValue
        self.plainText = plainText
        self.fullTextData = fullTextData
        self.isPlainTextTruncated = isPlainTextTruncated
        self.previewImageData = previewImageData
        self.imageData = imageData
        self.imageUTType = imageMetadata?.utTypeIdentifier
        self.imageByteCount = imageMetadata?.byteCount
        self.imagePixelWidth = imageMetadata?.pixelWidth
        self.imagePixelHeight = imageMetadata?.pixelHeight
        self.appBundleID = appBundleID
        self.appLocalizedName = appLocalizedName
        self.appIconDominantColorHex = appIconDominantColorHex
        self.appIconData = appIconData
        self.groupId = groupId
        self.groupIdsRaw = groupIdsRaw
        self.customTitle = customTitle
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
        self.isPinned = isPinned
        self.rtfData = rtfData
        self.richTextArchiveData = richTextArchiveData
        self.sourcePlatformRawValue = sourcePlatformRawValue
        self.sourceDeviceName = sourceDeviceName
        self.captureMethodRawValue = captureMethodRawValue
        self.captureSessionID = captureSessionID
    }
}

extension ClipboardRecord {
    /// 完整文本:优先取 `fullTextData`(超大文本全文),否则回退到内联 `plainText`。
    /// ⚠️ 会触碰 `.externalStorage` getter,只应在 store actor 的 fetch 上调用,
    /// 不要在 UI 层持有的 model 实例上访问。
    var resolvedPlainText: String? {
        if let fullTextData, let fullText = String(data: fullTextData, encoding: .utf8) {
            return fullText
        }
        return plainText
    }
}
