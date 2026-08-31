import Foundation

private enum ProbeError: Error {
    case unavailable
}

@main
enum ClipboardRuntimeBootstrapPolicyTests {
    static func main() throws {
        try testPreferredRuntime()
        try testCloudFallsBackToLocal()
        try testPersistentStoreFallsBackToMemory()
        print("ClipboardRuntimeBootstrapPolicyTests passed")
    }

    private static func testPreferredRuntime() throws {
        let resolution = try ClipboardRuntimeBootstrapPolicy.resolve(
            preferredSyncEnabled: false,
            makePersistentRuntime: { $0 ? "cloud" : "local" },
            makeInMemoryRuntime: { "memory" }
        )
        precondition(resolution.value == "local")
        precondition(resolution.source == .preferred)
    }

    private static func testCloudFallsBackToLocal() throws {
        let resolution = try ClipboardRuntimeBootstrapPolicy.resolve(
            preferredSyncEnabled: true,
            makePersistentRuntime: { syncEnabled in
                if syncEnabled { throw ProbeError.unavailable }
                return "local"
            },
            makeInMemoryRuntime: { "memory" }
        )
        precondition(resolution.value == "local")
        precondition(resolution.source == .localFallback)
    }

    private static func testPersistentStoreFallsBackToMemory() throws {
        let resolution = try ClipboardRuntimeBootstrapPolicy.resolve(
            preferredSyncEnabled: false,
            makePersistentRuntime: { _ in throw ProbeError.unavailable },
            makeInMemoryRuntime: { "memory" }
        )
        precondition(resolution.value == "memory")
        precondition(resolution.source == .memoryFallback)
        precondition(resolution.preferredError != nil)
    }
}
