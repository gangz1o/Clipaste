import Foundation

/// 轻量级链接 metadata 引擎。通过 URLSession 在后台抓取 HTML，解析标题和 favicon，

struct HTMLPage: Sendable {
    let html: String
    let finalURL: URL
}

nonisolated enum LinkMetadataResourceKind: Sendable {
    case html
    case icon

    func accepts(mimeType: String?) -> Bool {
        guard let mimeType = mimeType?.lowercased() else { return true }

        switch self {
        case .html:
            return mimeType == "text/html" || mimeType == "application/xhtml+xml"
        case .icon:
            return mimeType.hasPrefix("image/") || mimeType == "application/octet-stream"
        }
    }
}
