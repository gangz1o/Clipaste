import AppKit
import Foundation

enum ClipboardLinkOpeningService {
    nonisolated static func url(from item: ClipboardItem) -> URL? {
        let candidates = [
            item.rawText,
            item.previewText,
            item.textPreview.isEmpty ? nil : item.textPreview
        ]

        for candidate in candidates {
            guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.isEmpty == false,
                  let url = validatedHTTPURL(from: text) else {
                continue
            }

            return url
        }

        return nil
    }

    @MainActor
    static func defaultBrowserName(for url: URL) -> String? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }

        if let bundle = Bundle(url: applicationURL) {
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String

            if let displayName, displayName.isEmpty == false {
                return displayName
            }

            if let bundleName, bundleName.isEmpty == false {
                return bundleName
            }
        }

        let fallbackName = applicationURL.deletingPathExtension().lastPathComponent
        return fallbackName.isEmpty ? nil : fallbackName
    }

    @MainActor
    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

private extension ClipboardLinkOpeningService {
    nonisolated static func validatedHTTPURL(from string: String) -> URL? {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              host.isEmpty == false,
              let url = components.url else {
            return nil
        }

        return url
    }
}
