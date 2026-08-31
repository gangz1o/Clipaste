import Foundation

@MainActor
protocol ClipboardCaptureDraining: AnyObject {
    func stopMonitoringAndDrain() async
}

protocol ClipboardStorageDraining: Sendable {
    func drain() async
}

enum ClipboardStorageTransitionBarrier {
    @MainActor
    static func quiesce(
        capture: any ClipboardCaptureDraining,
        sourceStorage: any ClipboardStorageDraining,
        cancelMaintenance: () async -> Void
    ) async {
        await capture.stopMonitoringAndDrain()
        await cancelMaintenance()
        await sourceStorage.drain()
    }
}
