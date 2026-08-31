import Foundation
import SwiftData

extension StorageManager {
    nonisolated
    func shutdown() async {
        let runningTasks = prepareForShutdown()

        for task in runningTasks {
            task.cancel()
        }

        for task in runningTasks {
            _ = await task.result
        }
    }

    nonisolated
    func drain() async {
        while true {
            let retryTasks = takeScheduledRetryTasks()
            for task in retryTasks {
                task.cancel()
            }
            for task in retryTasks {
                _ = await task.result
            }

            let runningTasks = snapshotActiveTasks()
            guard runningTasks.isEmpty == false || retryTasks.isEmpty == false else { return }

            for task in runningTasks {
                await task.value
            }
        }
    }

    nonisolated func spawnTrackedTask(
        priority: TaskPriority,
        linkMetadataHash: String? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        let taskID = UUID()

        taskLock.lock()
        guard isShuttingDown == false else {
            taskLock.unlock()
            return
        }

        if let linkMetadataHash,
           isLinkMetadataAttemptAllowedLocked(hash: linkMetadataHash) == false {
            taskLock.unlock()
            return
        }

        if let linkMetadataHash,
           activeLinkMetadataHashes.insert(linkMetadataHash).inserted == false {
            taskLock.unlock()
            return
        }

        let task = Task.detached(priority: priority) { [weak self] in
            defer {
                self?.finishTrackedTask(
                    id: taskID,
                    linkMetadataHash: linkMetadataHash
                )
            }
            await operation()
        }

        activeTasks[taskID] = task
        taskLock.unlock()
    }

    nonisolated func finishTrackedTask(id: UUID, linkMetadataHash: String?) {
        taskLock.lock()
        activeTasks.removeValue(forKey: id)
        if let linkMetadataHash {
            activeLinkMetadataHashes.remove(linkMetadataHash)
        }
        taskLock.unlock()
    }

    nonisolated func isLinkMetadataAttemptAllowedLocked(hash: String) -> Bool {
        guard let failure = linkMetadataFailures[hash] else { return true }
        guard Date() >= failure.nextAllowedDate else { return false }

        if failure.attemptCount >= LinkMetadataFailureState.maximumAttemptCount {
            linkMetadataFailures.removeValue(forKey: hash)
        }
        return true
    }

    nonisolated func recordLinkMetadataOutcome(
        hash: String,
        succeeded: Bool
    ) -> Duration? {
        taskLock.lock()
        defer { taskLock.unlock() }

        if succeeded {
            linkMetadataFailures.removeValue(forKey: hash)
            return nil
        }

        let previousAttempts = linkMetadataFailures[hash]?.attemptCount ?? 0
        let attemptCount = previousAttempts + 1
        let delaySeconds = min(60, 5 * (1 << min(previousAttempts, 3)))
        linkMetadataFailures[hash] = LinkMetadataFailureState(
            attemptCount: attemptCount,
            nextAllowedDate: Date().addingTimeInterval(TimeInterval(delaySeconds))
        )

        if linkMetadataFailures.count > LinkMetadataFailureState.maximumTrackedHashCount,
           let oldest = linkMetadataFailures.min(by: {
               $0.value.nextAllowedDate < $1.value.nextAllowedDate
           })?.key {
            linkMetadataFailures.removeValue(forKey: oldest)
        }

        guard attemptCount < LinkMetadataFailureState.maximumAttemptCount else { return nil }
        return .seconds(delaySeconds)
    }

    nonisolated func scheduleLinkMetadataRetry(
        hash: String,
        urlString: String,
        delay: Duration
    ) {
        let retryID = UUID()
        let task = Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            self?.finishScheduledRetry(id: retryID)
            self?.processLinkMetadata(hash: hash, urlString: urlString)
        }

        taskLock.lock()
        guard isShuttingDown == false else {
            taskLock.unlock()
            task.cancel()
            return
        }
        scheduledRetryTasks[retryID] = task
        taskLock.unlock()
    }

    nonisolated func finishScheduledRetry(id: UUID) {
        taskLock.lock()
        scheduledRetryTasks.removeValue(forKey: id)
        taskLock.unlock()
    }

    nonisolated func takeScheduledRetryTasks() -> [Task<Void, Never>] {
        taskLock.lock()
        defer { taskLock.unlock() }
        let tasks = Array(scheduledRetryTasks.values)
        scheduledRetryTasks.removeAll(keepingCapacity: false)
        return tasks
    }

    nonisolated func prepareForShutdown() -> [Task<Void, Never>] {
        taskLock.lock()
        defer { taskLock.unlock() }

        isShuttingDown = true
        let tasks = Array(activeTasks.values) + Array(scheduledRetryTasks.values)
        scheduledRetryTasks.removeAll(keepingCapacity: false)
        return tasks
    }

    nonisolated var acceptsNewTasks: Bool {
        taskLock.lock()
        defer { taskLock.unlock() }
        return isShuttingDown == false
    }

    nonisolated func snapshotActiveTasks() -> [Task<Void, Never>] {
        taskLock.lock()
        defer { taskLock.unlock() }
        return Array(activeTasks.values)
    }
}
