import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func refreshCloudStoreDiagnostics(using storage: StorageManager) async {
        cloudStoreDiagnostics = await storage.diagnosticsSnapshot()
    }

    func refreshCloudServerDiagnostics() async {
        do {
            cloudServerDiagnostics = try await CloudKitServerDiagnosticsService.snapshot(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            cloudServerDiagnosticsError = nil
        } catch {
            cloudServerDiagnosticsError = CloudSyncErrorFormatter.message(for: error)
            appendDiagnostic(
                level: .warning,
                message: ClipboardSyncDiagnosticMessage(
                    "CloudKit server diagnostics failed: %@",
                    arguments: [.string(cloudServerDiagnosticsError ?? error.localizedDescription)]
                )
            )
        }
    }


    func resetClipboardSnapshotSignature(using storage: StorageManager) async {
        clipboardSnapshotSignature = await makeClipboardSnapshotSignature(using: storage)
    }

    func updateClipboardSnapshotSignature(_ latestSignature: String) -> Bool {
        defer { clipboardSnapshotSignature = latestSignature }
        guard let clipboardSnapshotSignature else { return true }
        return clipboardSnapshotSignature != latestSignature
    }

    func makeClipboardSnapshotSignature(using storage: StorageManager) async -> String {
        let groups = await storage.fetchGroups()
        let items = await storage.fetchItemsPage(
            searchText: "",
            fetchLimit: ClipboardHistoryWarmCache.defaultLimit,
            offset: 0
        )
        let groupSignature = groups.map { group in
            [
                group.id,
                group.name,
                group.systemIconName ?? "",
                String(group.sortOrder)
            ].joined(separator: "|")
        }.joined(separator: "\n")

        let itemSignature = items.map { item in
            [
                item.id.uuidString,
                item.contentHash,
                String(item.timestamp.timeIntervalSinceReferenceDate),
                item.isPinned ? "1" : "0",
                item.groupIDs.joined(separator: ",")
            ].joined(separator: "|")
        }.joined(separator: "\n")

        return "groups:\n\(groupSignature)\nitems:\n\(itemSignature)"
    }

    func scheduleWarmCacheRefresh(using storage: StorageManager, routeKey: String) {
        Task.detached(priority: .background) {
            let warmItems = await storage.fetchItemsPage(
                searchText: "",
                fetchLimit: ClipboardHistoryWarmCache.defaultLimit,
                offset: 0
            )
            await ClipboardHistoryWarmCache.shared.update(items: warmItems, routeKey: routeKey)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardWarmCacheDidChange,
                    object: nil,
                    userInfo: ["routeKey": routeKey]
                )
            }
        }
    }


    func appendDiagnostic(level: ClipboardSyncDiagnosticLevel, message: ClipboardSyncDiagnosticMessage) {
        diagnosticsEntries.insert(
            ClipboardSyncDiagnosticEntry(level: level, message: message),
            at: 0
        )

        if diagnosticsEntries.count > maxDiagnosticEntries {
            diagnosticsEntries.removeLast(diagnosticsEntries.count - maxDiagnosticEntries)
        }
    }
}
