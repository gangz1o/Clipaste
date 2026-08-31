import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func resetCloudLocalCacheRuntime() async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        let sourceRuntime = currentRuntime
        await ClipboardStorageTransitionBarrier.quiesce(
            capture: ClipboardMonitor.shared,
            sourceStorage: sourceRuntime.storage
        ) {
            let pendingRemoteRepair = self.remoteRepairTask
            pendingRemoteRepair?.cancel()
            await pendingRemoteRepair?.value
            self.remoteRepairTask = nil
        }

        appendDiagnostic(
            level: .warning,
            message: ClipboardSyncDiagnosticMessage("Resetting local iCloud cache. Cloud records will be kept")
        )

        do {
            try await CloudSyncAvailabilityService.preflight(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )

            let localRuntime: ClipboardRuntime
            if let cachedLocalRuntime = self.localRuntime {
                localRuntime = cachedLocalRuntime
            } else {
                localRuntime = try await makeRuntimeOffMain(syncEnabled: false)
                self.localRuntime = localRuntime
            }
            await localRuntime.storage.drain()

            var retiringCloudRuntime = cloudRuntime
            if retiringCloudRuntime == nil, currentRuntime.syncEnabled {
                retiringCloudRuntime = currentRuntime
            }
            if let retiringCloudRuntime {
                await retiringCloudRuntime.storage.shutdown()
            }

            activateRuntime(
                localRuntime,
                syncEnabled: false,
                persistPreference: false,
                updateLastSyncDate: false,
                notifyObservers: false
            )
            cloudRuntime = nil
            retiringCloudRuntime = nil
            await Task.yield()

            try await Task.detached(priority: .utility) {
                try ClipboardModelContainerFactory.resetCloudStoreArtifacts()
            }.value

            let cloudRuntime = try await makeRuntimeOffMain(syncEnabled: true)
            self.cloudRuntime = cloudRuntime
            activateRuntime(
                cloudRuntime,
                syncEnabled: true,
                persistPreference: true,
                updateLastSyncDate: true
            )

            try await cloudRuntime.storage.touchSyncAnchor()
            await refreshCloudStoreDiagnostics(using: cloudRuntime.storage)
            scheduleRemoteImportRepair()

            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("Local iCloud cache reset completed")
            )
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Local iCloud cache reset failed: %@",
                    arguments: [.string(message)]
                )
            )

            if currentRuntime.syncEnabled == false {
                defaults.set(false, forKey: Keys.syncEnabled)
                isSyncEnabled = false
            }
        }

        ClipboardMonitor.shared.startMonitoring()
        isSyncing = false
        processPendingSyncRequestIfNeeded()
    }

}
