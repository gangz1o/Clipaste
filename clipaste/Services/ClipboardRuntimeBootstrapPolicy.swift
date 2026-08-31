import Foundation

enum ClipboardRuntimeBootstrapSource: Sendable, Equatable {
    case preferred
    case localFallback
    case memoryFallback
}

struct ClipboardRuntimeBootstrapResolution<Value> {
    let value: Value
    let source: ClipboardRuntimeBootstrapSource
    let preferredError: Error?
}

struct ClipboardRuntimeBootstrapFailure: LocalizedError {
    let persistentError: Error
    let memoryError: Error

    var errorDescription: String? {
        "Persistent storage failed: \(persistentError.localizedDescription); in-memory recovery failed: \(memoryError.localizedDescription)"
    }
}

enum ClipboardRuntimeBootstrapPolicy {
    static func resolve<Value>(
        preferredSyncEnabled: Bool,
        makePersistentRuntime: (Bool) throws -> Value,
        makeInMemoryRuntime: () throws -> Value
    ) throws -> ClipboardRuntimeBootstrapResolution<Value> {
        do {
            return ClipboardRuntimeBootstrapResolution(
                value: try makePersistentRuntime(preferredSyncEnabled),
                source: .preferred,
                preferredError: nil
            )
        } catch {
            let preferredError = error

            if preferredSyncEnabled,
               let localRuntime = try? makePersistentRuntime(false) {
                return ClipboardRuntimeBootstrapResolution(
                    value: localRuntime,
                    source: .localFallback,
                    preferredError: preferredError
                )
            }

            do {
                return ClipboardRuntimeBootstrapResolution(
                    value: try makeInMemoryRuntime(),
                    source: .memoryFallback,
                    preferredError: preferredError
                )
            } catch {
                throw ClipboardRuntimeBootstrapFailure(
                    persistentError: preferredError,
                    memoryError: error
                )
            }
        }
    }
}
