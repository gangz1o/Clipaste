import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func scheduleRemoteImportRepair() {
        remoteRepairTask?.cancel()
        remoteRepairTask = Task { [weak self] in
            guard let self else { return }

            // Single tail-pass catches CloudKit deliveries that finish a
            // short moment after eventChanged fires; the no-op signature
            // check makes this cheap when nothing actually changed.
            await self.refreshAfterRemoteImport()
            await self.refreshAfterRemoteImportPasses(delays: [1_500_000_000])
        }
    }

    func handleExportEventCompletion(errorMessage: String?) {
        if let errorMessage {
            guard syncError != errorMessage else { return }

            syncError = errorMessage
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "iCloud export failed: %@",
                    arguments: [.string(errorMessage)]
                )
            )
            return
        }

        lastSyncDate = Date()
        defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)

        if syncError != nil {
            syncError = nil
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("iCloud export recovered after previous failure")
            )
        }
    }

    func nudgeCurrentRoute() async {
        guard currentRuntime.syncEnabled else { return }

        do {
            try await currentRuntime.storage.touchSyncAnchor()
            scheduleRemoteImportRepair()
        } catch {
            syncError = CloudSyncErrorFormatter.message(for: error)
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Sync anchor update failed: %@",
                    arguments: [.string(syncError ?? error.localizedDescription)]
                )
            )
        }
    }

    func refreshAfterRemoteImport() async {
        // Detect actual content change first via the lightweight signature;
        // skip dedup entirely on no-op CloudKit pings. When a change is
        // observed, dedup is throttled (default: at most once per 10 min) —
        // ordinary capture-time dedup is already handled inline in upsert.
        let latestSignature = await makeClipboardSnapshotSignature(using: currentRuntime.storage)
        let didChange = updateClipboardSnapshotSignature(latestSignature)

        guard didChange else { return }

        let repairedCount = await repairDuplicateRecordsIfThrottled(using: currentRuntime.storage)
        await refreshCloudStoreDiagnostics(using: currentRuntime.storage)

        NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        scheduleWarmCacheRefresh(using: currentRuntime.storage, routeKey: rootIdentity)

        guard repairedCount > 0 else { return }

        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Repaired %@ duplicate synced record(s)",
                arguments: [.count(repairedCount)]
            )
        )
    }

    func refreshAfterRemoteImportPasses(delays: [UInt64]) async {
        for delay in delays {
            try? await Task.sleep(nanoseconds: delay)
            guard Task.isCancelled == false else { return }
            await refreshAfterRemoteImport()
        }
    }

}
