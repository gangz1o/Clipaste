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
    case link      // 智能嗅探：合法 URL
    case code      // 智能嗅探：代码特征匹配

    /// Filter Bar / 溢出菜单中的智能分类标题（随 SwiftUI 语言环境解析）。
    @MainActor
    var localizedFilterTitle: LocalizedStringResource {
        switch self {
        case .text: return LocalizedStringResource("Smart Filter Text")
        case .image: return LocalizedStringResource("Smart Filter Image")
        case .fileURL: return LocalizedStringResource("Smart Filter File")
        case .color: return LocalizedStringResource("Smart Filter Color")
        case .link: return LocalizedStringResource("Smart Filter Link")
        case .code: return LocalizedStringResource("Smart Filter Code")
        }
    }

    /// Filter Bar 图标
    var systemImage: String {
        switch self {
        case .text:    return "doc.text"
        case .image:   return "photo"
        case .fileURL: return "doc"
        case .color:   return "paintpalette"
        case .link:    return "link"
        case .code:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Filter Bar 可选分类（精简展示，不含 color/fileURL）
    static let filterCategories: [ClipboardContentType] = [.text, .link, .image]
}

enum ClipboardBuiltInGroup: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case favorites

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .favorites:
            return "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites:
            return "star.fill"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .favorites:
            return item.isPinned
        }
    }
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
    let hasImagePreview: Bool
    let hasImageData: Bool
    let imageUTType: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let fileURL: String?
    let resolvedFileURL: URL?
    let fileDisplayPath: String?
    let fileDisplayName: String?
    let fileRepresentsImage: Bool
    var groupIDs: [String] // 所属分组 ID 集合
    var customTitle: String? // 用户手动添加的标题
    var linkTitle: String?     // 链接预览：网页标题（后台 metadata 引擎抓取）
    var linkIconData: Data?    // 链接预览：网站图标数据
    var isPinned: Bool         // 固定状态
    let hasRTF: Bool           // ⚠️ 架构红线：仅轻量标记，不持有富文本二进制
    let sourcePlatformRawValue: String
    let sourceDeviceName: String?
    let captureMethodRawValue: String
    let captureSessionID: UUID?

    // ⚠️ 性能核心：全部为 let 常量，初始化时一次性计算完毕，SwiftUI 重绘读取耗时 = 0
    let previewText: String?
    let isFastLink: Bool
    let fastParsedColor: Color?

    nonisolated init(
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
        hasImagePreview: Bool = false,
        hasImageData: Bool = false,
        imageUTType: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        fileURL: String? = nil,
        groupId: String? = nil,
        groupIDs: [String] = [],
        customTitle: String? = nil,
        linkTitle: String? = nil,
        linkIconData: Data? = nil,
        isPinned: Bool = false,
        hasRTF: Bool = false,
        sourcePlatformRawValue: String = "macOS",
        sourceDeviceName: String? = nil,
        captureMethodRawValue: String = "monitor",
        captureSessionID: UUID? = nil
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
        self.hasImagePreview = hasImagePreview
        self.hasImageData = hasImageData
        self.imageUTType = imageUTType
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.fileURL = fileURL
        let resolvedFileURL = ClipboardFileReference.resolvedURL(from: fileURL)
        self.resolvedFileURL = resolvedFileURL
        self.fileDisplayPath = resolvedFileURL?.path
        if let path = resolvedFileURL?.path, !path.isEmpty {
            self.fileDisplayName = (path as NSString).lastPathComponent
        } else if let fileURL, !fileURL.isEmpty {
            self.fileDisplayName = fileURL
        } else {
            self.fileDisplayName = nil
        }
        self.fileRepresentsImage = resolvedFileURL.map { ClipboardFileReference.isLikelyImageFileURL($0) } ?? false
        self.groupIDs = normalizedGroupIDs
        self.customTitle = customTitle
        self.linkTitle = linkTitle
        self.linkIconData = linkIconData
        self.isPinned = isPinned
        self.hasRTF = hasRTF
        self.sourcePlatformRawValue = sourcePlatformRawValue
        self.sourceDeviceName = sourceDeviceName
        self.captureMethodRawValue = captureMethodRawValue
        self.captureSessionID = captureSessionID

        // --- 性能隔离区：只在初始化时执行一次，使用 utf8.count 极速字节级判断 ---
        let sourceText = rawText ?? (textPreview.isEmpty ? nil : textPreview)
        if let text = sourceText {
            if text.utf8.count > 3000 {
                // 超大文本：物理截断，直接封死正则和链接判断
                self.previewText = String(text.prefix(1000)) + "\n" + String(localized: "Text preview truncated for performance.")
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
    // ⚠️ 等价性收窄：只比较"身份 + 易变标志"。
    // 1. `id` + `contentHash` 锁定身份；包含 contentHash 是因为编辑/迁移可能在同一
    //    UUID 下替换内容，UI 需要触发 diff。
    // 2. `timestamp` 反映置顶/重排序。
    // 3. 剩余字段是"会驱动 UI 重渲染"的可变标志（标题、链接元数据、固定、分组）。
    // 4. 大字段（linkIconData、rawText、fileDisplayPath 等）从比较和哈希中移除：
    //    这些要么由 id+contentHash 隐含锁定，要么会让 Published diff / Set / SwiftUI
    //    自带 .id() 路径在每次刷新时跑昂贵的字节级比较。
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.contentHash == rhs.contentHash &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isPinned == rhs.isPinned &&
        lhs.customTitle == rhs.customTitle &&
        lhs.linkTitle == rhs.linkTitle &&
        lhs.groupIDs == rhs.groupIDs &&
        lhs.hasRTF == rhs.hasRTF &&
        lhs.hasImagePreview == rhs.hasImagePreview &&
        lhs.hasImageData == rhs.hasImageData
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(contentHash)
        hasher.combine(timestamp)
        hasher.combine(isPinned)
    }
}

extension ClipboardItem {
    /// 卡片角标等内容类型文案（与筛选标签共用同一套 String Catalog 键）。
    @MainActor
    func typeBadgeTitle() -> LocalizedStringResource {
        switch contentType {
        case .text: return LocalizedStringResource("Smart Filter Text")
        case .image: return LocalizedStringResource("Smart Filter Image")
        case .fileURL: return LocalizedStringResource("Smart Filter File")
        case .color: return LocalizedStringResource("Smart Filter Color")
        case .link: return LocalizedStringResource("Smart Filter Link")
        case .code: return LocalizedStringResource("Smart Filter Code")
        }
    }

    var groupId: String? {
        groupIDs.first
    }

    var trimmedCustomTitle: String? {
        let normalized = customTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, normalized.isEmpty == false else {
            return nil
        }
        return normalized
    }

    var hasCustomTitle: Bool {
        trimmedCustomTitle != nil
    }

    var imagePixelSize: CGSize? {
        guard let imagePixelWidth, let imagePixelHeight else { return nil }
        guard imagePixelWidth > 0, imagePixelHeight > 0 else { return nil }
        return CGSize(width: imagePixelWidth, height: imagePixelHeight)
    }

    var isScreenPinEligible: Bool {
        contentType == .image || (contentType == .fileURL && fileRepresentsImage)
    }

    private nonisolated static func normalizedGroupIDs(primaryGroupID: String?, groupIDs: [String]) -> [String] {
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

extension ClipboardItem {
    nonisolated static func searchableTextValue(
        plainText: String?,
        customTitle: String?,
        linkTitle: String?
    ) -> String? {
        let candidates = [customTitle, plainText, linkTitle]
            .compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }

        guard candidates.isEmpty == false else {
            return nil
        }

        return candidates.joined(separator: "\n")
    }
}

// 计算属性已迁移至 init 中的存储属性，此处不再需要 extension

extension ClipboardItem {
    nonisolated static func appIconName(for bundleIdentifier: String?) -> String {
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
