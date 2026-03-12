import Foundation

/// 轻量级链接标题抓取引擎（仅抓取标题，不下载图标）。
/// 使用 URLSession 直接获取 HTML，解析 og:title / &lt;title&gt;，
/// 完全不依赖 LinkPresentation / WebKit。
struct LinkMetadataEngine {

    static func fetchMetadata(for urlString: String) async -> (title: String?, iconData: Data?) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              !shouldSkip(host: host),
              let pageURL = components.url else {
            return (nil, nil)
        }

        guard let html = await fetchHTML(url: pageURL) else { return (nil, nil) }
        let title = extractTitle(from: html)
        return (title, nil)          // 不抓图标，直接返回 nil
    }

    // MARK: - HTML Fetch

    private static func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Title Parser

    private static func extractTitle(from html: String) -> String? {
        let patterns: [String] = [
            #"<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']"#,
            #"<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:title["\']"#,
            #"<title[^>]*>([^<]+)</title>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let decoded = decodeHTMLEntities(String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines))
                return decoded.isEmpty ? nil : decoded
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func decodeHTMLEntities(_ s: String) -> String {
        var result = s
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, char) in map { result = result.replacingOccurrences(of: entity, with: char) }
        return result
    }

    private static func shouldSkip(host: String) -> Bool {
        host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("192.168.")
    }
}

