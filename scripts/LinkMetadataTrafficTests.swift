import Foundation

@main
enum LinkMetadataTrafficTests {
    static func main() async {
        await testSmallHTMLAndIcon()
        await testKnownOversizedHTMLStopsBeforeBody()
        await testUnknownLengthHTMLIsCancelledAtLimit()
        await testWrongMIMETypeIsRejected()
        await testKnownOversizedIconStopsBeforeBody()
        await testIconCandidateLimit()
        await testConcurrentFetchLimit()
        await testQueuedFetchCancellation()
        testDisplayModePolicy()
        print("LinkMetadataTrafficTests passed")
    }

    private static func testSmallHTMLAndIcon() async {
        let html = Data(
            "<html><head><title>Bounded title</title><link rel=\"icon\" href=\"/icon.png\"></head></html>".utf8
        )
        let icon = Data([0x89, 0x50, 0x4E, 0x47])
        MockURLProtocol.state.reset(plans: [
            "/page": MockHTTPPlan(
                mimeType: "text/html; charset=utf-8",
                contentLength: html.count,
                chunks: [html]
            ),
            "/icon.png": MockHTTPPlan(
                mimeType: "image/png",
                contentLength: icon.count,
                chunks: [icon]
            )
        ])

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/page",
            session: makeSession(),
            resolver: MockHostResolver()
        )

        precondition(result.title == "Bounded title")
        precondition(result.iconData == icon)
    }

    private static func testKnownOversizedHTMLStopsBeforeBody() async {
        let oversizedLength = LinkMetadataEngine.maxHTMLByteCount + 1
        MockURLProtocol.state.reset(plans: [
            "/known-oversized": MockHTTPPlan(
                mimeType: "text/html",
                contentLength: oversizedLength,
                chunks: [Data(repeating: 0x61, count: 1_024)],
                delay: .milliseconds(20)
            )
        ])

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/known-oversized",
            session: makeSession(),
            resolver: MockHostResolver()
        )
        await waitForCancellation()

        precondition(result.title == nil && result.iconData == nil)
        let metrics = MockURLProtocol.state.metrics()
        precondition(metrics.deliveredByteCount == 0)
        precondition(metrics.stopCount > 0)
    }

    private static func testUnknownLengthHTMLIsCancelledAtLimit() async {
        let chunkSize = 8 * 1_024
        let fullByteCount = LinkMetadataEngine.maxHTMLByteCount * 2
        let chunks = Array(
            repeating: Data(repeating: 0x61, count: chunkSize),
            count: fullByteCount / chunkSize
        )
        MockURLProtocol.state.reset(plans: [
            "/streamed-oversized": MockHTTPPlan(
                mimeType: "text/html",
                chunks: chunks,
                delay: .milliseconds(1)
            )
        ])

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/streamed-oversized",
            session: makeSession(),
            resolver: MockHostResolver()
        )
        await waitForCancellation()

        precondition(result.title == nil && result.iconData == nil)
        let metrics = MockURLProtocol.state.metrics()
        precondition(metrics.deliveredByteCount < fullByteCount)
        precondition(metrics.stopCount > 0)
    }

    private static func testWrongMIMETypeIsRejected() async {
        let body = Data("<title>Must not parse</title>".utf8)
        MockURLProtocol.state.reset(plans: [
            "/binary": MockHTTPPlan(
                mimeType: "application/octet-stream",
                contentLength: body.count,
                chunks: [body],
                delay: .milliseconds(20)
            )
        ])

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/binary",
            session: makeSession(),
            resolver: MockHostResolver()
        )

        precondition(result.title == nil && result.iconData == nil)
        precondition(MockURLProtocol.state.metrics().deliveredByteCount == 0)
    }

    private static func testKnownOversizedIconStopsBeforeBody() async {
        let html = Data("<title>Keep title</title><link rel=\"icon\" href=\"/oversized-icon.png\">".utf8)
        let iconChunkSize = 8 * 1_024
        let iconBodySize = LinkMetadataEngine.maxIconByteCount * 2
        let iconChunks = Array(
            repeating: Data(repeating: 0x89, count: iconChunkSize),
            count: iconBodySize / iconChunkSize
        )
        MockURLProtocol.state.reset(plans: [
            "/oversized-icon-page": MockHTTPPlan(
                mimeType: "text/html",
                contentLength: html.count,
                chunks: [html]
            ),
            "/oversized-icon.png": MockHTTPPlan(
                mimeType: "image/png",
                contentLength: LinkMetadataEngine.maxIconByteCount + 1,
                chunks: iconChunks,
                delay: .milliseconds(1)
            )
        ])

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/oversized-icon-page",
            session: makeSession(),
            resolver: MockHostResolver()
        )
        await waitForCancellation()

        precondition(result.title == "Keep title")
        precondition(result.iconData == nil)
        let metrics = MockURLProtocol.state.metrics()
        precondition(metrics.deliveredByteCount < html.count + iconBodySize)
        precondition(metrics.stopCount > 0)
    }

    private static func testIconCandidateLimit() async {
        let iconLinks = (1...5)
            .map { "<link rel=\"icon\" href=\"/candidate-\($0).png\">" }
            .joined()
        let html = Data("<title>Candidate limit</title>\(iconLinks)".utf8)
        var plans: [String: MockHTTPPlan] = [
            "/many-icons": MockHTTPPlan(
                mimeType: "text/html",
                contentLength: html.count,
                chunks: [html]
            )
        ]
        for index in 1...5 {
            plans["/candidate-\(index).png"] = MockHTTPPlan(statusCode: 404)
        }
        MockURLProtocol.state.reset(plans: plans)

        let result = await LinkMetadataEngine.fetchMetadata(
            for: "https://metadata.test/many-icons",
            session: makeSession(),
            resolver: MockHostResolver()
        )

        precondition(result.title == "Candidate limit")
        precondition(result.iconData == nil)
        precondition(
            MockURLProtocol.state.requestCount(prefix: "/candidate-")
                == LinkMetadataEngine.maxIconCandidateCount
        )
    }

    private static func testConcurrentFetchLimit() async {
        let html = Data("<html><head><title>Concurrent</title></head></html>".utf8)
        var plans: [String: MockHTTPPlan] = [
            "/favicon.ico": MockHTTPPlan(statusCode: 404)
        ]
        for index in 0..<12 {
            plans["/concurrent-\(index)"] = MockHTTPPlan(
                mimeType: "text/html",
                contentLength: html.count,
                chunks: [html],
                delay: .milliseconds(40),
                tracksConcurrency: true
            )
        }
        MockURLProtocol.state.reset(plans: plans)
        let session = makeSession()

        await withTaskGroup(of: String?.self) { group in
            for index in 0..<12 {
                group.addTask {
                    await LinkMetadataEngine.fetchMetadata(
                        for: "https://metadata.test/concurrent-\(index)",
                        session: session,
                        resolver: MockHostResolver()
                    ).title
                }
            }

            for await title in group {
                precondition(title == "Concurrent")
            }
        }

        let peakConcurrency = MockURLProtocol.state.peakConcurrency()
        precondition(peakConcurrency > 1)
        precondition(peakConcurrency <= LinkMetadataEngine.maxConcurrentFetchCount)
    }

    private static func testQueuedFetchCancellation() async {
        let html = Data("<html><head><title>Cancelled</title></head></html>".utf8)
        var plans: [String: MockHTTPPlan] = [:]
        for index in 0..<8 {
            plans["/cancel-\(index)"] = MockHTTPPlan(
                mimeType: "text/html",
                contentLength: html.count,
                chunks: [html],
                delay: .seconds(2),
                tracksConcurrency: true
            )
        }
        MockURLProtocol.state.reset(plans: plans)
        let session = makeSession()
        let tasks = (0..<8).map { index in
            Task {
                await LinkMetadataEngine.fetchMetadata(
                    for: "https://metadata.test/cancel-\(index)",
                    session: session,
                    resolver: MockHostResolver()
                )
            }
        }

        for _ in 0..<100 {
            if MockURLProtocol.state.peakConcurrency() == LinkMetadataEngine.maxConcurrentFetchCount {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        precondition(
            MockURLProtocol.state.peakConcurrency() == LinkMetadataEngine.maxConcurrentFetchCount
        )

        tasks.forEach { $0.cancel() }
        for task in tasks {
            let result = await task.value
            precondition(result.title == nil && result.iconData == nil)
        }
    }

    private static func testDisplayModePolicy() {
        let suiteName = "LinkMetadataTrafficTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(ClipboardLinkDisplayMode.shouldFetchMetadata(defaults: defaults))
        defaults.set(ClipboardLinkDisplayMode.plain.rawValue, forKey: ClipboardLinkDisplayMode.defaultsKey)
        precondition(ClipboardLinkDisplayMode.shouldFetchMetadata(defaults: defaults) == false)
        defaults.set(ClipboardLinkDisplayMode.rich.rawValue, forKey: ClipboardLinkDisplayMode.defaultsKey)
        precondition(ClipboardLinkDisplayMode.shouldFetchMetadata(defaults: defaults))
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func waitForCancellation() async {
        for _ in 0..<20 {
            if MockURLProtocol.state.metrics().stopCount > 0 {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
