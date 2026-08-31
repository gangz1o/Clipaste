import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func repairDuplicateRecordsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = DedupThrottle.currentVersion
        let storedVersion = defaults.integer(forKey: Keys.duplicateRepairVersion)
        guard storedVersion < currentVersion else {
            // Treat the last completed run as "recent enough" so the
            // remote-import path's throttle does not redundantly retrigger
            // dedup right after startup.
            lastDuplicateRepairDate = Date()
            return 0
        }

        let repairedCount = await storage.repairDuplicateRecords()
        defaults.set(currentVersion, forKey: Keys.duplicateRepairVersion)
        lastDuplicateRepairDate = Date()
        return repairedCount
    }

    func recoverLocalFavoritesIfNeeded() async throws {
        guard currentRuntime.syncEnabled else { return }
        guard defaults.integer(forKey: Keys.favoriteRecoveryVersion) < FavoriteRecovery.currentVersion else {
            return
        }

        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage("Starting local favorite recovery for the cloud route")
        )

        do {
            let sourceRuntime: ClipboardRuntime
            if let localRuntime {
                sourceRuntime = localRuntime
            } else {
                let runtime = try await makeRuntimeOffMain(syncEnabled: false)
                localRuntime = runtime
                sourceRuntime = runtime
            }

            let batchSize = 128
            var offset = 0
            var recoveredRecordCount = 0
            var recoveredGroupIDs: Set<String> = []

            while true {
                let payload = try await sourceRuntime.storage.exportPinnedRecordBatch(
                    offset: offset,
                    limit: batchSize
                )
                guard payload.records.isEmpty == false else { break }
                try await currentRuntime.storage.importStoreExport(payload)
                recoveredRecordCount += payload.records.count
                recoveredGroupIDs.formUnion(payload.groups.map(\.id))
                offset += payload.records.count
                await Task.yield()
            }

            defaults.set(FavoriteRecovery.currentVersion, forKey: Keys.favoriteRecoveryVersion)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Local favorite recovery completed. Records: %@, groups: %@",
                    arguments: [.count(recoveredRecordCount), .count(recoveredGroupIDs.count)]
                )
            )
        } catch {
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Local favorite recovery failed and will retry: %@",
                    arguments: [.string(CloudSyncErrorFormatter.message(for: error))]
                )
            )
            throw error
        }
    }

    func repairDuplicateRecordsIfThrottled(using storage: StorageManager) async -> Int {
        if let lastDuplicateRepairDate,
           Date().timeIntervalSince(lastDuplicateRepairDate) < DedupThrottle.minimumInterval {
            return 0
        }

        let repairedCount = await storage.repairDuplicateRecords()
        lastDuplicateRepairDate = Date()
        return repairedCount
    }

    func repairOversizedTextRecordsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = 1
        let storedVersion = defaults.integer(forKey: Keys.oversizedTextRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let repairedCount = await storage.repairOversizedInlineTextRecords()
        defaults.set(currentVersion, forKey: Keys.oversizedTextRepairVersion)
        return repairedCount
    }

    func repairTextClassificationsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = ClipboardContentClassifier.repairVersion
        let storedVersion = defaults.integer(forKey: Keys.textClassificationRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let repairedCount = await storage.repairTextClassificationsIfNeeded()
        defaults.set(currentVersion, forKey: Keys.textClassificationRepairVersion)
        return repairedCount
    }

    func repairAppIconColorsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = 1
        let storedVersion = defaults.integer(forKey: Keys.appIconColorRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let bundleIDs = await storage.fetchDistinctAppBundleIDsForColorRepair()
        guard bundleIDs.isEmpty == false else {
            defaults.set(currentVersion, forKey: Keys.appIconColorRepairVersion)
            return 0
        }

        var colorsByBundleID: [String: String] = [:]
        colorsByBundleID.reserveCapacity(bundleIDs.count)

        for (index, bundleID) in bundleIDs.enumerated() {
            if index > 0, index.isMultiple(of: 8) {
                await Task.yield()
            }
            guard let icon = AppIconManager.shared.getIcon(for: bundleID),
                  let colorHex = icon.dominantColorHex() else {
                continue
            }

            colorsByBundleID[bundleID] = colorHex
        }

        let repairedCount = await storage.repairAppIconDominantColors(using: colorsByBundleID)
        defaults.set(currentVersion, forKey: Keys.appIconColorRepairVersion)
        return repairedCount
    }

    func repairAppIconDataIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = 1
        let storedVersion = defaults.integer(forKey: Keys.appIconDataRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let bundleIDs = await storage.fetchDistinctAppBundleIDsMissingIconData()
        guard bundleIDs.isEmpty == false else {
            defaults.set(currentVersion, forKey: Keys.appIconDataRepairVersion)
            return 0
        }

        var iconDataByBundleID: [String: Data] = [:]
        iconDataByBundleID.reserveCapacity(bundleIDs.count)

        for (index, bundleID) in bundleIDs.enumerated() {
            if index > 0, index.isMultiple(of: 8) {
                await Task.yield()
            }
            guard let iconData = AppIconManager.shared.iconPNGData(for: bundleID) else {
                continue
            }

            iconDataByBundleID[bundleID] = iconData
        }

        let repairedCount = await storage.repairAppIconData(using: iconDataByBundleID)
        defaults.set(currentVersion, forKey: Keys.appIconDataRepairVersion)
        return repairedCount
    }

}
