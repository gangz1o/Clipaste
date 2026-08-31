import Foundation

/// 轻量级链接 metadata 引擎。通过 URLSession 在后台抓取 HTML，解析标题和 favicon，

final class LinkMetadataDataLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let stateLock = NSLock()
    private let maximumByteCount: Int
    private let resourceKind: LinkMetadataResourceKind
    private let resolver: any LinkMetadataHostResolving
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse)?, Never>?
    private var response: HTTPURLResponse?
    private var receivedData = Data()
    private var isCompleted = false

    init(
        configuration: URLSessionConfiguration,
        maximumByteCount: Int,
        resourceKind: LinkMetadataResourceKind,
        resolver: any LinkMetadataHostResolving
    ) {
        self.maximumByteCount = maximumByteCount
        self.resourceKind = resourceKind
        self.resolver = resolver
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func load(request: URLRequest) async -> (Data, HTTPURLResponse)? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                stateLock.lock()
                guard isCompleted == false else {
                    stateLock.unlock()
                    continuation.resume(returning: nil)
                    return
                }

                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                stateLock.unlock()

                if Task.isCancelled {
                    finish(result: nil, cancelTask: true)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.finish(result: nil, cancelTask: true)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              LinkMetadataNetworkPolicy.isAllowedURLFromBackground(url, resolver: resolver) else {
            completionHandler(nil)
            finish(result: nil, cancelTask: true)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let finalURL = httpResponse.url,
              LinkMetadataNetworkPolicy.isAllowedURLFromBackground(finalURL, resolver: resolver),
              resourceKind.accepts(mimeType: httpResponse.mimeType),
              httpResponse.expectedContentLength <= Int64(maximumByteCount) else {
            completionHandler(.cancel)
            finish(result: nil, cancelTask: true)
            return
        }

        stateLock.lock()
        guard isCompleted == false else {
            stateLock.unlock()
            completionHandler(.cancel)
            return
        }

        self.response = httpResponse
        if httpResponse.expectedContentLength > 0 {
            receivedData.reserveCapacity(Int(httpResponse.expectedContentLength))
        }
        stateLock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        guard isCompleted == false,
              data.count <= maximumByteCount - receivedData.count else {
            stateLock.unlock()
            finish(result: nil, cancelTask: true)
            return
        }

        receivedData.append(data)
        stateLock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stateLock.lock()
        let result: (Data, HTTPURLResponse)?
        if error == nil, let response {
            result = (receivedData, response)
        } else {
            result = nil
        }
        stateLock.unlock()

        finish(result: result, cancelTask: false)
    }

    private func finish(result: (Data, HTTPURLResponse)?, cancelTask: Bool) {
        stateLock.lock()
        guard isCompleted == false else {
            stateLock.unlock()
            return
        }

        isCompleted = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        stateLock.unlock()

        if cancelTask {
            task?.cancel()
            session.invalidateAndCancel()
        } else {
            session.finishTasksAndInvalidate()
        }
        continuation?.resume(returning: result)
    }
}
