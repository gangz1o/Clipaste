import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func rebuildRuntime(syncEnabled: Bool, mergeCurrentStore: Bool) async {
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
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Starting runtime rebuild. Target route: %@, merge current store: %@",
                arguments: [.route(syncEnabled ? "cloud" : "local"), .bool(mergeCurrentStore)]
            )
        )

        do {
            let targetRuntime: ClipboardRuntime
            let shouldMergeStores = mergeCurrentStore && sourceRuntime.syncEnabled != syncEnabled
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Current route: %@. Cross-route merge: %@",
                    arguments: [.route(sourceRuntime.syncEnabled ? "cloud" : "local"), .bool(shouldMergeStores)]
                )
            )

            if syncEnabled {
                try await CloudSyncAvailabilityService.preflight(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage("iCloud account preflight passed")
                )
            }

            targetRuntime = try runtime(for: syncEnabled)
            await targetRuntime.storage.drain()
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Target runtime is ready: %@",
                    arguments: [.route(syncEnabled ? "cloud" : "local")]
                )
            )

            if shouldMergeStores {
                let mergeCounts = try await mergeStoreInBatches(
                    from: sourceRuntime.storage,
                    into: targetRuntime.storage
                )
                let repairedDuplicateCount = await targetRuntime.storage.repairDuplicateRecords()
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Cross-route data merge completed. Records: %@, groups: %@",
                        arguments: [.count(mergeCounts.records), .count(mergeCounts.groups)]
                    )
                )
                if repairedDuplicateCount > 0 {
                    appendDiagnostic(
                        level: .info,
                        message: ClipboardSyncDiagnosticMessage(
                            "Repaired %@ duplicate synced record(s)",
                            arguments: [.count(repairedDuplicateCount)]
                        )
                    )
                }
            }

            try await bootstrapper.importLegacyStoreIfNeeded(into: targetRuntime.storage)
            let repairedDuplicateCount = await targetRuntime.storage.repairDuplicateRecords()
            if repairedDuplicateCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ duplicate synced record(s)",
                        arguments: [.count(repairedDuplicateCount)]
                    )
                )
            }
            if syncEnabled {
                await refreshCloudStoreDiagnostics(using: targetRuntime.storage)
            }

            activateRuntime(
                targetRuntime,
                syncEnabled: syncEnabled,
                persistPreference: true,
                updateLastSyncDate: true
            )
            await resetClipboardSnapshotSignature(using: targetRuntime.storage)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Runtime switch completed. Current route: %@",
                    arguments: [.route(syncEnabled ? "cloud" : "local")]
                )
            )
            scheduleMaintenance()
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Runtime switch failed: %@",
                    arguments: [.string(message)]
                )
            )

            // 构建失败时，UI 必须反映当前真实路由，而不是用户刚才试图切换到的目标状态。
            isSyncEnabled = currentRuntime.syncEnabled
            defaults.set(currentRuntime.syncEnabled, forKey: Keys.syncEnabled)

            if currentRuntime.syncEnabled == false {
                runtimeGeneration = UUID()
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        }

        ClipboardMonitor.shared.startMonitoring()
        isSyncing = false
        processPendingSyncRequestIfNeeded()
    }

    func mergeStoreInBatches(
        from sourceStorage: StorageManager,
        into targetStorage: StorageManager
    ) async throws -> (records: Int, groups: Int) {
        let groups = try await sourceStorage.exportGroups()
        if groups.isEmpty == false {
            try await targetStorage.importStoreExport(
                ClipboardStoreExport(records: [], groups: groups)
            )
        }

        let batchSize = 128
        let importedRecordCount = try await BoundedBatchTransfer.run(
            batchSize: batchSize,
            loadBatch: { offset, limit in
                try await sourceStorage.exportRecordBatch(offset: offset, limit: limit)
            },
            consumeBatch: { records in
                try await targetStorage.importStoreExport(
                    ClipboardStoreExport(records: records, groups: [])
                )
            }
        )

        return (records: importedRecordCount, groups: groups.count)
    }

}
