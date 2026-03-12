import AppKit
import Foundation

struct ClipboardGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var iconName: String
}

enum ClipboardContentType: String, Codable {
    case text
    case image
    case fileURL
    case color
}

/// UI-facing DTO used by the ViewModel and SwiftUI views.
struct ClipboardItem: Identifiable, Hashable, @unchecked Sendable {
    let id: UUID
    let contentType: ClipboardContentType
    let contentHash: String
    let textPreview: String
    let searchableText: String?
    let sourceBundleIdentifier: String?
    let appName: String
    let appIcon: NSImage?
    let appIconName: String // Or you can use NSImage, but keeping it simple for now
    let timestamp: Date
    let rawText: String?
    let imagePath: String?
    let thumbnailURL: URL?
    let fileURL: String?
    var groupId: String? // 所属分组 ID，nil 表示未分组
    var linkTitle: String?     // 链接预览：网页标题（LinkPresentation 抓取）
    var linkIconData: Data?    // 链接预览：网站图标数据

    init(
        id: UUID = UUID(),
        contentType: ClipboardContentType = .text,
        contentHash: String,
        textPreview: String,
        searchableText: String? = nil,
        sourceBundleIdentifier: String? = nil,
        appName: String,
        appIcon: NSImage? = nil,
        appIconName: String,
        timestamp: Date = Date(),
        rawText: String? = nil,
        imagePath: String? = nil,
        thumbnailURL: URL? = nil,
        fileURL: String? = nil,
        groupId: String? = nil,
        linkTitle: String? = nil,
        linkIconData: Data? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.contentHash = contentHash
        self.textPreview = textPreview
        self.searchableText = searchableText
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.appName = appName
        self.appIcon = appIcon
        self.appIconName = appIconName
        self.timestamp = timestamp
        self.rawText = rawText
        self.imagePath = imagePath
        self.thumbnailURL = thumbnailURL
        self.fileURL = fileURL
        self.groupId = groupId
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
    }
}

extension ClipboardItem {
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.contentType == rhs.contentType &&
        lhs.contentHash == rhs.contentHash &&
        lhs.textPreview == rhs.textPreview &&
        lhs.searchableText == rhs.searchableText &&
        lhs.sourceBundleIdentifier == rhs.sourceBundleIdentifier &&
        lhs.appName == rhs.appName &&
        lhs.appIconName == rhs.appIconName &&
        lhs.timestamp == rhs.timestamp &&
        lhs.rawText == rhs.rawText &&
        lhs.imagePath == rhs.imagePath &&
        lhs.thumbnailURL == rhs.thumbnailURL &&
        lhs.fileURL == rhs.fileURL &&
        lhs.groupId == rhs.groupId &&
        lhs.linkTitle == rhs.linkTitle &&
        lhs.linkIconData == rhs.linkIconData
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(contentType)
        hasher.combine(contentHash)
        hasher.combine(textPreview)
        hasher.combine(searchableText)
        hasher.combine(sourceBundleIdentifier)
        hasher.combine(appName)
        hasher.combine(appIconName)
        hasher.combine(timestamp)
        hasher.combine(rawText)
        hasher.combine(imagePath)
        hasher.combine(thumbnailURL)
        hasher.combine(fileURL)
        hasher.combine(groupId)
        hasher.combine(linkTitle)
        hasher.combine(linkIconData)
    }
}

extension ClipboardItem {
    static func appIconName(for bundleIdentifier: String?) -> String {
        switch bundleIdentifier {
        case "com.apple.Safari":
            return "safari"
        case "com.apple.dt.Xcode":
            return "chevron.left.forwardslash.chevron.right"
        case "com.apple.Terminal":
            return "terminal"
        case "com.apple.Notes":
            return "note.text"
        case "com.apple.MobileSMS":
            return "message"
        default:
            return "app.fill"
        }
    }
}
