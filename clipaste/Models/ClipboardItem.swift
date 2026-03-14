import AppKit
import Foundation
import SwiftUI

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
    let originalImageURL: URL?  // QuickLook 高清预览：指向 Originals/ 下的全尺寸原图
    let fileURL: String?
    var groupIDs: [String] // 所属分组 ID 集合
    var linkTitle: String?     // 链接预览：网页标题（LinkPresentation 抓取）
    var linkIconData: Data?    // 链接预览：网站图标数据
    var isPinned: Bool         // 固定状态

    // ⚠️ 性能核心：全部为 let 常量，初始化时一次性计算完毕，SwiftUI 重绘读取耗时 = 0
    let previewText: String?
    let isFastLink: Bool
    let fastParsedColor: Color?

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
        originalImageURL: URL? = nil,
        fileURL: String? = nil,
        groupId: String? = nil,
        groupIDs: [String] = [],
        linkTitle: String? = nil,
        linkIconData: Data? = nil,
        isPinned: Bool = false
    ) {
        let normalizedGroupIDs = ClipboardItem.normalizedGroupIDs(primaryGroupID: groupId, groupIDs: groupIDs)

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
        self.originalImageURL = originalImageURL
        self.fileURL = fileURL
        self.groupIDs = normalizedGroupIDs
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
        self.isPinned = isPinned

        // --- 性能隔离区：只在初始化时执行一次，使用 utf8.count 极速字节级判断 ---
        let sourceText = rawText ?? (textPreview.isEmpty ? nil : textPreview)
        if let text = sourceText {
            if text.utf8.count > 3000 {
                // 超大文本：物理截断，直接封死正则和链接判断
                self.previewText = String(text.prefix(1000)) + "\n... (文本过长，已折叠)"
                self.isFastLink = false
                self.fastParsedColor = nil
            } else {
                // 正常短文本：完整保留并执行轻量级判断
                self.previewText = text
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.isFastLink = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
                self.fastParsedColor = text.utf8.count < 100 ? ColorParser.extractColor(from: text) : nil
            }
        } else {
            self.previewText = nil
            self.isFastLink = false
            self.fastParsedColor = nil
        }
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
        lhs.groupIDs == rhs.groupIDs &&
        lhs.linkTitle == rhs.linkTitle &&
        lhs.linkIconData == rhs.linkIconData &&
        lhs.isPinned == rhs.isPinned
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
        hasher.combine(groupIDs)
        hasher.combine(linkTitle)
        hasher.combine(linkIconData)
        hasher.combine(isPinned)
    }
}

extension ClipboardItem {
    var groupId: String? {
        groupIDs.first
    }

    private static func normalizedGroupIDs(primaryGroupID: String?, groupIDs: [String]) -> [String] {
        var result: [String] = []

        if let primaryGroupID, !primaryGroupID.isEmpty {
            result.append(primaryGroupID)
        }

        for id in groupIDs where !id.isEmpty && result.contains(id) == false {
            result.append(id)
        }

        return result
    }
}

// 计算属性已迁移至 init 中的存储属性，此处不再需要 extension

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
