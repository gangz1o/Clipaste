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
        clipboardSnapshotSignature = await makeClipboardSnapshot(using: storage).signature
    }

    func updateClipboardSnapshotSignature(_ latestSignature: ClipboardSnapshotSignature) -> Bool {
        defer { clipboardSnapshotSignature = latestSignature }
        guard let clipboardSnapshotSignature else { return true }
        return clipboardSnapshotSignature != latestSignature
    }

    func makeClipboardSnapshot(
        using storage: StorageManager
    ) async -> (signature: ClipboardSnapshotSignature, items: [ClipboardItem]) {
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

        let entries = items.map { item in
            ClipboardSnapshotSignature.Entry(
                contentHash: item.contentHash,
                timestamp: item.timestamp.timeIntervalSinceReferenceDate,
                fingerprint: [
                    item.id.uuidString,
                    item.isPinned ? "1" : "0",
                    String(item.topPinOrder),
                    item.groupIDs.joined(separator: ",")
                ].joined(separator: "|")
            )
        }

        let signature = ClipboardSnapshotSignature(
            groupSignature: groupSignature,
            entries: entries,
            windowLimit: ClipboardHistoryWarmCache.defaultLimit
        )
        return (signature, items)
    }

    func scheduleWarmCacheRefresh(using storage: StorageManager, routeKey: String) {
        Task.detached(priority: .background) {
            let warmItems = await storage.fetchItemsPage(
                searchText: "",
                fetchLimit: ClipboardHistoryWarmCache.defaultLimit,
                offset: 0
            )
            await Self.publishWarmCache(warmItems, routeKey: routeKey)
        }
    }

    /// 已经拿到首屏数据时直接更新 warm cache，省掉一次重复查询。
    func publishWarmCache(_ items: [ClipboardItem], routeKey: String) {
        Task.detached(priority: .background) {
            await Self.publishWarmCache(items, routeKey: routeKey)
        }
    }

    private nonisolated static func publishWarmCache(_ warmItems: [ClipboardItem], routeKey: String) async {
        await ClipboardHistoryWarmCache.shared.update(items: warmItems, routeKey: routeKey)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .clipboardWarmCacheDidChange,
                object: nil,
                userInfo: ["routeKey": routeKey]
            )
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
