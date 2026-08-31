import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    var storage: StorageManager {
        currentRuntime.storage
    }

    var rootIdentity: String {
        "\(isSyncEnabled)-\(runtimeGeneration.uuidString)"
    }

    var diagnosticsSnapshot: ClipboardSyncDiagnosticsSnapshot {
        ClipboardSyncDiagnosticsSnapshot(
            activeRoute: currentRuntime.syncEnabled ? "cloud" : "local",
            preferredSyncEnabled: defaults.bool(forKey: Keys.syncEnabled),
            currentSyncEnabled: isSyncEnabled,
            pendingSyncEnabled: pendingSyncEnabled,
            isSyncing: isSyncing,
            cloudKitContainerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier,
            cloudKitEnvironment: ClipboardModelContainerFactory.cloudKitEnvironmentName,
            cloudKitAccountRecordName: cloudKitAccountRecordName,
            cloudStoreRecordCount: cloudStoreDiagnostics?.recordCount,
            cloudStoreGroupCount: cloudStoreDiagnostics?.groupCount,
            cloudServerRecordCount: cloudServerDiagnostics?.recordCount,
            cloudServerGroupCount: cloudServerDiagnostics?.groupCount,
            cloudServerError: cloudServerDiagnosticsError,
            latestRecordFingerprints: cloudStoreDiagnostics?.latestRecordFingerprints ?? [],
            localRuntimeReady: localRuntime != nil,
            cloudRuntimeReady: cloudRuntime != nil,
            localStorePath: ClipboardModelContainerFactory.localStoreURL.path,
            cloudStorePath: ClipboardModelContainerFactory.cloudStoreURL.path,
            runtimeGeneration: runtimeGeneration.uuidString,
            lastSyncDate: lastSyncDate,
            lastError: syncError
        )
    }

    func setSyncEnabled(_ enabled: Bool) {
        guard enabled != isSyncEnabled else {
            pendingSyncEnabled = nil
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Ignored duplicate sync toggle request: %@",
                    arguments: [.syncState(enabled)]
                )
            )
            return
        }

        if isSyncing {
            pendingSyncEnabled = enabled
            appendDiagnostic(
                level: .warning,
                message: ClipboardSyncDiagnosticMessage(
                    "Sync toggle already in progress. Queued request: %@",
                    arguments: [.syncState(enabled)]
                )
            )
            return
        }

        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Received sync toggle request: %@",
                arguments: [.syncState(enabled)]
            )
        )
        Task {
            await rebuildRuntime(syncEnabled: enabled, mergeCurrentStore: true)
        }
    }

    func refreshCurrentRoute() {
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Received sync status refresh request. Current route: %@",
                arguments: [.route(isSyncEnabled ? "cloud" : "local")]
            )
        )
        Task {
            await refreshSyncStatus()
        }
    }

    func resetCloudLocalCache() {
        guard isSyncing == false else { return }

        appendDiagnostic(
            level: .warning,
            message: ClipboardSyncDiagnosticMessage("Received local iCloud cache reset request")
        )

        Task {
            await resetCloudLocalCacheRuntime()
        }
    }

    func handleAppBecameActive() {
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage("App became active; nudging current iCloud route")
        )

        Task {
            await nudgeCurrentRoute()
        }
    }

    func diagnosticsReport(locale: Locale = .current) -> String {
        let snapshot = diagnosticsSnapshot
        let reportDate = Date().formatted(date: .numeric, time: .standard)
        let entries = diagnosticsEntries.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.level.rawValue)] \($0.localizedMessage(locale: locale))"
        }.joined(separator: "\n")

        return """
        Clipaste Sync Diagnostics
        Generated: \(reportDate)
        Active Route: \(snapshot.activeRoute)
        Preferred Sync Enabled: \(snapshot.preferredSyncEnabled)
        Current Sync Enabled: \(snapshot.currentSyncEnabled)
        Pending Sync Request: \(snapshot.pendingSyncEnabled.map(String.init(describing:)) ?? "none")
        Is Syncing: \(snapshot.isSyncing)
        CloudKit Container: \(snapshot.cloudKitContainerIdentifier)
        CloudKit Environment: \(snapshot.cloudKitEnvironment)
        CloudKit Account Record Available: \(snapshot.cloudKitAccountRecordName != nil)
        Cloud Store Record Count: \(snapshot.cloudStoreRecordCount.map(String.init) ?? "unknown")
        Cloud Store Group Count: \(snapshot.cloudStoreGroupCount.map(String.init) ?? "unknown")
        Cloud Server Record Count: \(snapshot.cloudServerRecordCount.map(String.init) ?? "unknown")
        Cloud Server Group Count: \(snapshot.cloudServerGroupCount.map(String.init) ?? "unknown")
        Cloud Server Error: \(snapshot.cloudServerError ?? "none")
        Latest Record Fingerprints: \(snapshot.latestRecordFingerprints.isEmpty ? "unknown" : snapshot.latestRecordFingerprints.joined(separator: ", "))
        Local Runtime Ready: \(snapshot.localRuntimeReady)
        Cloud Runtime Ready: \(snapshot.cloudRuntimeReady)
        Runtime Generation: \(snapshot.runtimeGeneration)
        Last Sync Date: \(snapshot.lastSyncDate?.formatted(date: .numeric, time: .standard) ?? "none")
        Last Error: \(snapshot.lastError ?? "none")
        Local Store Path: \(snapshot.localStorePath)
        Cloud Store Path: \(snapshot.cloudStorePath)
        Recent Events:
        \(entries.isEmpty ? "none" : entries)
        """
    }

}
