import Foundation

extension AIExecutionService {
    func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExecutionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIExecutionError.requestFailed(httpResponse.statusCode, message)
        }

        return data
    }

    func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AIExecutionError.requestTimedOut
            }

            guard let value = try await group.next() else {
                throw AIExecutionError.requestTimedOut
            }

            group.cancelAll()
            return value
        }
    }
}
