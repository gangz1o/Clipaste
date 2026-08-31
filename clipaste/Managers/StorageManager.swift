import Foundation
import SwiftData

final class StorageManager: @unchecked Sendable, ClipboardStorageDraining {
    nonisolated static var shared: StorageManager {
        ClipboardStorageRegistry.storage()
    }

    nonisolated let container: ModelContainer
    let storeActor: ClipboardStoreActor
    let cleanupActor: ClipboardStoreActor
    nonisolated let taskLock = NSLock()
    nonisolated(unsafe) var activeTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) var scheduledRetryTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) var activeLinkMetadataHashes: Set<String> = []
    nonisolated(unsafe) var linkMetadataFailures: [String: LinkMetadataFailureState] = [:]
    nonisolated(unsafe) var isShuttingDown = false

    nonisolated init(modelContainer: ModelContainer) {
        self.container = modelContainer
        self.storeActor = ClipboardStoreActor(modelContainer: modelContainer)
        self.cleanupActor = ClipboardStoreActor(modelContainer: modelContainer)
    }

    // Keep interactive reads off the shared write actor to avoid QoS inversions.
    private func makeReadActor() -> ClipboardStoreActor {
        ClipboardStoreActor(modelContainer: container)
    }

    /// 所有 UI / MainActor 可达的 async 读操作统一经过这里:
    /// 用 `Task.detached(priority: .userInitiated)` 把对 SwiftData `@ModelActor`
    /// (其底层执行器运行在 Background QoS 的私有队列上) 的等待动作
    /// 搬离 user-interactive 主线程,彻底消除
    /// "User-interactive thread waiting on Background QoS" 这类 Hang Risk 告警。
    /// 调用方只需像普通 async 函数一样 `await` 即可,不用手写 detached。
    nonisolated
    func detachedRead<T: Sendable>(
        _ operation: @Sendable @escaping () async -> T
    ) async -> T {
        await Task.detached(priority: .userInitiated) {
            await operation()
        }.value
    }
}
