import Foundation

struct ClipboardLinkPreviewViewModel: Hashable {
    let title: String
    let domain: String
    let displayURL: String
    let fullURL: String
    let iconData: Data?

    init(item: ClipboardItem) {
        let rawURL = Self.preferredURLText(from: item)
        let components = URLComponents(string: rawURL)
        let host = components?.host?.lowercased()
        let normalizedDomain = Self.displayDomain(from: host)
        let metadataTitle = item.linkTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.title = Self.preferredTitle(
            customTitle: item.trimmedCustomTitle,
            metadataTitle: metadataTitle,
            domain: normalizedDomain
        )
        self.domain = normalizedDomain
        self.displayURL = rawURL
        self.fullURL = rawURL
        self.iconData = item.linkIconData
    }
}

private extension ClipboardLinkPreviewViewModel {
    static func preferredURLText(from item: ClipboardItem) -> String {
        let candidates = [
            item.rawText,
            item.previewText,
            item.textPreview.isEmpty ? nil : item.textPreview
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false } ?? ""
    }

    static func preferredTitle(customTitle: String?, metadataTitle: String?, domain: String) -> String {
        if let customTitle, customTitle.isEmpty == false {
            return customTitle
        }

        if let metadataTitle, metadataTitle.isEmpty == false {
            return metadataTitle
        }

        return domain
    }

    static func displayDomain(from host: String?) -> String {
        guard let host, host.isEmpty == false else {
            return String(localized: "Link")
        }

        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }

        return host
    }

}
