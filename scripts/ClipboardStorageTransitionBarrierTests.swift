import Foundation

private actor EventLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

@MainActor
private final class CaptureSpy: ClipboardCaptureDraining {
    let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func stopMonitoringAndDrain() async {
        await log.append("capture-drained")
    }
}

private struct StorageSpy: ClipboardStorageDraining {
    let log: EventLog

    func drain() async {
        await log.append("storage-drained")
    }
}

@main
enum ClipboardStorageTransitionBarrierTests {
    @MainActor
    static func main() async {
        let log = EventLog()
        await ClipboardStorageTransitionBarrier.quiesce(
            capture: CaptureSpy(log: log),
            sourceStorage: StorageSpy(log: log)
        ) {
            await log.append("maintenance-cancelled")
        }

        let events = await log.snapshot()
        precondition(events == [
            "capture-drained",
            "maintenance-cancelled",
            "storage-drained"
        ])
        print("ClipboardStorageTransitionBarrierTests passed")
    }
}
