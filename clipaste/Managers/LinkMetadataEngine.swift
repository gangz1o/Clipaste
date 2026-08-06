import Foundation

/// 轻量级链接 metadata 引擎。通过 URLSession 在后台抓取 HTML，解析标题和 favicon，
/// 不依赖 LinkPresentation / WebKit，避免把网页加载工作放进 UI 层。
struct LinkMetadataEngine {
    nonisolated private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    nonisolated static let maxHTMLByteCount = 512 * 1024
    nonisolated static let maxIconByteCount = 256 * 1024
    nonisolated static let maxIconCandidateCount = 4

    nonisolated static func fetchMetadata(
        for urlString: String,
        session: URLSession = .shared
    ) async -> (title: String?, iconData: Data?) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let pageURL = validatedHTTPURL(from: trimmed),
              let page = await fetchHTML(url: pageURL, session: session) else {
            return (nil, nil)
        }

        async let title = extractTitle(from: page.html)
        async let iconData = fetchIconData(
            from: page.html,
            pageURL: page.finalURL,
            session: session
        )

        return await (title, iconData)
    }

    // MARK: - HTML Fetch

    nonisolated private static func fetchHTML(url: URL, session: URLSession) async -> HTMLPage? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-\(Self.maxHTMLByteCount)", forHTTPHeaderField: "Range")

        guard let (data, response) = await fetchLimitedData(
            request: request,
            session: session,
            maximumByteCount: Self.maxHTMLByteCount,
            resourceKind: .html
        ) else {
            return nil
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)

        guard let html, html.isEmpty == false else {
            return nil
        }

        return HTMLPage(html: html, finalURL: response.url ?? url)
    }

    // MARK: - Title Parser

    nonisolated private static func extractTitle(from html: String) async -> String? {
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

    // MARK: - Icon Fetch

    nonisolated private static func fetchIconData(
        from html: String,
        pageURL: URL,
        session: URLSession
    ) async -> Data? {
        let candidates = iconCandidates(from: html, pageURL: pageURL)

        for iconURL in candidates {
            guard Task.isCancelled == false else { return nil }

            if let data = await fetchIconData(url: iconURL, session: session) {
                return data
            }
        }

        return nil
    }

    nonisolated private static func fetchIconData(url: URL, session: URLSession) async -> Data? {
        guard isAllowedHTTPURL(url) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-\(Self.maxIconByteCount)", forHTTPHeaderField: "Range")

        guard let (data, _) = await fetchLimitedData(
            request: request,
            session: session,
            maximumByteCount: Self.maxIconByteCount,
            resourceKind: .icon
        ), data.isEmpty == false else {
            return nil
        }

        return data
    }

    nonisolated private static func iconCandidates(from html: String, pageURL: URL) -> [URL] {
        let linkCandidates = extractIconHrefs(from: html)
            .compactMap { absoluteURL(from: $0, relativeTo: pageURL) }
            .filter(isAllowedHTTPURL)

        let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
        return Array(
            uniqueURLs(linkCandidates + [fallback].compactMap { $0 })
                .prefix(Self.maxIconCandidateCount)
        )
    }

    nonisolated private static func extractIconHrefs(from html: String) -> [String] {
        let pattern = #"<link\b[^>]*>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])

            guard let rel = attributeValue(named: "rel", in: tag)?.lowercased(),
                  rel.contains("icon") else {
                return nil
            }

            return attributeValue(named: "href", in: tag)
        }
    }

    nonisolated private static func attributeValue(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b\#(escapedName)\s*=\s*(["'])(.*?)\1"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let valueRange = Range(match.range(at: 2), in: tag) else {
            return nil
        }

        let value = decodeHTMLEntities(String(tag[valueRange]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Helpers

    nonisolated private static func decodeHTMLEntities(_ s: String) -> String {
        var result = s
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, char) in map { result = result.replacingOccurrences(of: entity, with: char) }
        return result
    }

    nonisolated private static func validatedHTTPURL(from string: String) -> URL? {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              shouldSkip(host: host) == false,
              let url = components.url else {
            return nil
        }

        return url
    }

    nonisolated private static func isAllowedHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              shouldSkip(host: host) == false else {
            return false
        }

        return true
    }

    nonisolated private static func absoluteURL(from rawValue: String, relativeTo baseURL: URL) -> URL? {
        URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }

    nonisolated private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []

        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }

        return result
    }

    nonisolated private static func fetchLimitedData(
        request: URLRequest,
        session: URLSession,
        maximumByteCount: Int,
        resourceKind: LinkMetadataResourceKind
    ) async -> (Data, HTTPURLResponse)? {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse

        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            return nil
        }

        var completed = false
        defer {
            if completed == false {
                bytes.task.cancel()
            }
        }

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let finalURL = httpResponse.url,
              isAllowedHTTPURL(finalURL),
              resourceKind.accepts(mimeType: httpResponse.mimeType),
              httpResponse.expectedContentLength <= Int64(maximumByteCount) else {
            return nil
        }

        var data = Data()
        if httpResponse.expectedContentLength > 0 {
            data.reserveCapacity(Int(httpResponse.expectedContentLength))
        }

        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumByteCount else {
                    return nil
                }
                data.append(byte)
            }
        } catch {
            return nil
        }

        completed = true
        return (data, httpResponse)
    }

    nonisolated private static func shouldSkip(host: String) -> Bool {
        host == "localhost"
            || host == "::1"
            || host.hasPrefix("127.")
            || host.hasPrefix("10.")
            || host.hasPrefix("192.168.")
            || isPrivate172Host(host)
    }

    nonisolated private static func isPrivate172Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count >= 2,
              parts[0] == "172",
              let second = Int(parts[1]) else {
            return false
        }

        return 16...31 ~= second
    }
}

private struct HTMLPage: Sendable {
    let html: String
    let finalURL: URL
}

private nonisolated enum LinkMetadataResourceKind: Sendable {
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
