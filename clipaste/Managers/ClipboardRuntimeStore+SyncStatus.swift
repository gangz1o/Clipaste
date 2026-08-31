import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func refreshSyncStatus() async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Refreshing sync status. Current route: %@",
                arguments: [.route(currentRuntime.syncEnabled ? "cloud" : "local")]
            )
        )

        defer {
            isSyncing = false
            processPendingSyncRequestIfNeeded()
        }

        guard currentRuntime.syncEnabled else {
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("Local route active. Refresh only updated the timestamp")
            )
            return
        }

        do {
            try await CloudSyncAvailabilityService.preflight(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
            try await currentRuntime.storage.touchSyncAnchor()
            await refreshCloudStoreDiagnostics(using: currentRuntime.storage)
            await refreshAfterRemoteImport()
            await refreshAfterRemoteImportPasses(delays: [500_000_000, 2_000_000_000])
            scheduleRemoteImportRepair()
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("iCloud connection status refreshed successfully")
            )
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Sync status refresh failed: %@",
                    arguments: [.string(message)]
                )
            )
        }
    }

    func activateRuntime(
        _ runtime: ClipboardRuntime,
        syncEnabled: Bool,
        persistPreference: Bool,
        updateLastSyncDate: Bool,
        notifyObservers: Bool = true
    ) {
        currentRuntime = runtime
        container = runtime.container
        isSyncEnabled = syncEnabled
        runtimeGeneration = UUID()
        clipboardSnapshotSignature = nil

        if updateLastSyncDate {
            lastSyncDate = Date()
        }

        if persistPreference {
            defaults.set(syncEnabled, forKey: Keys.syncEnabled)
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
        }

        ClipboardStorageRegistry.update(storage: runtime.storage)
        ClipboardImagePipeline.shared.invalidateAll()
        if notifyObservers {
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            scheduleWarmCacheRefresh(using: runtime.storage, routeKey: rootIdentity)
        }
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Activated runtime: route=%@ generation=%@",
                arguments: [.route(syncEnabled ? "cloud" : "local"), .string(runtimeGeneration.uuidString)]
            )
        )
    }

    func runtime(for syncEnabled: Bool) throws -> ClipboardRuntime {
        if syncEnabled {
            if let cloudRuntime {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Reusing cached %@ runtime",
                        arguments: [.route("cloud")]
                    )
                )
                return cloudRuntime
            }

            let runtime = try containerFactory.makeRuntime(syncEnabled: true)
            cloudRuntime = runtime
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Created new %@ runtime",
                    arguments: [.route("cloud")]
                )
            )
            return runtime
        }

        if let localRuntime {
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Reusing cached %@ runtime",
                    arguments: [.route("local")]
                )
            )
            return localRuntime
        }

        let runtime = try containerFactory.makeRuntime(syncEnabled: false)
        localRuntime = runtime
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Created new %@ runtime",
                arguments: [.route("local")]
            )
        )
        return runtime
    }

    func makeRuntimeOffMain(syncEnabled: Bool) async throws -> ClipboardRuntime {
        let containerFactory = containerFactory
        return try await Task.detached(priority: .utility) {
            try containerFactory.makeRuntime(syncEnabled: syncEnabled)
        }.value
    }

}
