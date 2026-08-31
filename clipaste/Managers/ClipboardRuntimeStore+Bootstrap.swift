import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func performInitialBootstrap() async {
        isSyncing = true
        syncError = nil
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage("Starting startup legacy-store import check")
        )

        do {
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
            try await recoverLocalFavoritesIfNeeded()
            let repairedCount = await currentRuntime.storage.repairImportedMigrationTimestampsIfNeeded()
            let repairedClassificationCount = await repairTextClassificationsIfNeeded(using: currentRuntime.storage)
            let repairedAppIconColorCount = await repairAppIconColorsIfNeeded(using: currentRuntime.storage)
            let repairedAppIconDataCount = await repairAppIconDataIfNeeded(using: currentRuntime.storage)
            let repairedDuplicateCount = await repairDuplicateRecordsIfNeeded(using: currentRuntime.storage)
            let repairedOversizedTextCount = await repairOversizedTextRecordsIfNeeded(using: currentRuntime.storage)
            if currentRuntime.syncEnabled {
                cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                try await currentRuntime.storage.touchSyncAnchor()
                await refreshCloudStoreDiagnostics(using: currentRuntime.storage)
                await resetClipboardSnapshotSignature(using: currentRuntime.storage)
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
            if repairedCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ migrated record timestamp baseline issue(s)",
                        arguments: [.count(repairedCount)]
                    )
                )
            }
            if repairedClassificationCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ text/code classification record(s)",
                        arguments: [.count(repairedClassificationCount)]
                    )
                )
            }
            if repairedAppIconColorCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ app icon dominant color record(s)",
                        arguments: [.count(repairedAppIconColorCount)]
                    )
                )
            }
            if repairedAppIconDataCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ app icon image record(s)",
                        arguments: [.count(repairedAppIconDataCount)]
                    )
                )
            }
            if repairedDuplicateCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ duplicate synced record(s)",
                        arguments: [.count(repairedDuplicateCount)]
                    )
                )
            }
            if repairedOversizedTextCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ oversized text record(s)",
                        arguments: [.count(repairedOversizedTextCount)]
                    )
                )
            }
            scheduleWarmCacheRefresh(using: currentRuntime.storage, routeKey: rootIdentity)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("Startup legacy-store import check completed")
            )
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Startup bootstrap failed: %@",
                    arguments: [.string(message)]
                )
            )
        }

        isSyncing = false
        scheduleMaintenance()
        processPendingSyncRequestIfNeeded()
    }

}
