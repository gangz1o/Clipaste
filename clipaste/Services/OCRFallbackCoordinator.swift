import Foundation

enum OCRFallbackCoordinator {
    @MainActor
    static func run<Value>(
        primary: () async throws -> Value,
        fallback: (Error) async -> Value
    ) async -> Value? {
        guard Task.isCancelled == false else { return nil }

        do {
            let value = try await primary()
            guard Task.isCancelled == false else { return nil }
            return value
        } catch is CancellationError {
            return nil
        } catch {
            guard Task.isCancelled == false else { return nil }
            let value = await fallback(error)
            guard Task.isCancelled == false else { return nil }
            return value
        }
    }
}
