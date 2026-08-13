import Foundation

private struct MockHTTPPlan {
    let statusCode: Int
    let headers: [String: String]
    let chunks: [Data]
    let delay: Duration
    let tracksConcurrency: Bool

    init(
        statusCode: Int = 200,
        mimeType: String? = nil,
        contentLength: Int? = nil,
        chunks: [Data] = [],
        delay: Duration = .zero,
        tracksConcurrency: Bool = false
    ) {
        self.statusCode = statusCode
        var headers: [String: String] = [:]
        if let mimeType {
            headers["Content-Type"] = mimeType
        }
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        self.headers = headers
        self.chunks = chunks
        self.delay = delay
        self.tracksConcurrency = tracksConcurrency
    }
}

private final class MockHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var plans: [String: MockHTTPPlan] = [:]
    private var requestPaths: [String] = []
    private var deliveredByteCount = 0
    private var stopCount = 0
    private var activeRequestCount = 0
    private var peakActiveRequestCount = 0

    func reset(plans: [String: MockHTTPPlan]) {
        lock.withLock {
            generation += 1
            self.plans = plans
            requestPaths = []
            deliveredByteCount = 0
            stopCount = 0
            activeRequestCount = 0
            peakActiveRequestCount = 0
        }
    }

    func plan(for request: URLRequest) -> (plan: MockHTTPPlan, generation: Int)? {
        lock.withLock {
            let path = request.url?.path ?? ""
            requestPaths.append(path)
            guard let plan = plans[path] else { return nil }
            return (plan, generation)
        }
    }

    func recordDelivery(byteCount: Int, generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            deliveredByteCount += byteCount
        }
    }

    func recordStop(generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            stopCount += 1
        }
    }

    func recordStart(generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            activeRequestCount += 1
            peakActiveRequestCount = max(peakActiveRequestCount, activeRequestCount)
        }
    }

    func recordFinish(generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            activeRequestCount -= 1
        }
    }

    func requestCount(prefix: String) -> Int {
        lock.withLock {
            requestPaths.count { $0.hasPrefix(prefix) }
        }
    }

    func metrics() -> (deliveredByteCount: Int, stopCount: Int) {
        lock.withLock {
            (deliveredByteCount, stopCount)
        }
    }

    func peakConcurrency() -> Int {
        lock.withLock { peakActiveRequestCount }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = MockHTTPState()
    private var loadingTask: Task<Void, Never>?
    private var generation = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "metadata.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let responsePlan = Self.state.plan(for: request),
              let response = HTTPURLResponse(
                url: url,
                statusCode: responsePlan.plan.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: responsePlan.plan.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let plan = responsePlan.plan
        generation = responsePlan.generation
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        loadingTask = Task { [weak self] in
            guard let self else { return }
            if plan.tracksConcurrency {
                Self.state.recordStart(generation: generation)
            }
            defer {
                if plan.tracksConcurrency {
                    Self.state.recordFinish(generation: generation)
                }
            }

            for chunk in plan.chunks {
                if Task.isCancelled { return }
                if plan.delay != .zero {
                    try? await Task.sleep(for: plan.delay)
                }
                if Task.isCancelled { return }

                Self.state.recordDelivery(byteCount: chunk.count, generation: generation)
                client?.urlProtocol(self, didLoad: chunk)
            }

            if Task.isCancelled == false {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        Self.state.recordStop(generation: generation)
    }
}

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
            session: makeSession()
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
            session: makeSession()
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
            session: makeSession()
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
            session: makeSession()
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
            session: makeSession()
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
            session: makeSession()
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
                        session: session
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
                    session: session
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
