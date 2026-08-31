import Foundation

/// 轻量级链接 metadata 引擎。通过 URLSession 在后台抓取 HTML，解析标题和 favicon，

actor LinkMetadataConcurrencyLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []

    init(limit: Int) {
        availablePermits = limit
    }

    func acquire() async -> Bool {
        let waiterID = UUID()

        return await withTaskCancellationHandler {
            guard Task.isCancelled == false else { return false }

            if availablePermits > 0 {
                availablePermits -= 1
                return true
            }

            return await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    func release() {
        guard waiters.isEmpty == false else {
            availablePermits += 1
            return
        }

        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: true)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
