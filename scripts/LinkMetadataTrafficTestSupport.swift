import Foundation

struct MockHostResolver: LinkMetadataHostResolving {
    nonisolated func addresses(for host: String) -> [LinkMetadataResolvedAddress] {
        guard host == "metadata.test" else { return [] }
        return [
            LinkMetadataResolvedAddress(family: .ipv4, bytes: [93, 184, 216, 34])
        ]
    }
}

struct MockHTTPPlan: Sendable {
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

final class MockHTTPState: @unchecked Sendable {
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

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private final class WeakReference: @unchecked Sendable {
        weak var value: MockURLProtocol?

        init(_ value: MockURLProtocol) {
            self.value = value
        }
    }

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
        let deliveryGeneration = responsePlan.generation
        generation = deliveryGeneration
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let reference = WeakReference(self)
        loadingTask = Task { @Sendable [reference, plan, deliveryGeneration] in
            guard let protocolInstance = reference.value else { return }
            if plan.tracksConcurrency {
                Self.state.recordStart(generation: deliveryGeneration)
            }
            defer {
                if plan.tracksConcurrency {
                    Self.state.recordFinish(generation: deliveryGeneration)
                }
            }

            for chunk in plan.chunks {
                if Task.isCancelled { return }
                if plan.delay != .zero {
                    try? await Task.sleep(for: plan.delay)
                }
                if Task.isCancelled { return }

                Self.state.recordDelivery(byteCount: chunk.count, generation: deliveryGeneration)
                protocolInstance.client?.urlProtocol(protocolInstance, didLoad: chunk)
            }

            if Task.isCancelled == false {
                protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        Self.state.recordStop(generation: generation)
    }
}
