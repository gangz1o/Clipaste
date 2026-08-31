import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
extension ClipboardRuntimeStore {
    func processPendingSyncRequestIfNeeded() {
        guard let pendingSyncEnabled else { return }
        self.pendingSyncEnabled = nil

        guard pendingSyncEnabled != isSyncEnabled else { return }
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Starting queued sync request: %@",
                arguments: [.syncState(pendingSyncEnabled)]
            )
        )

        Task {
            await rebuildRuntime(syncEnabled: pendingSyncEnabled, mergeCurrentStore: true)
        }
    }

    func scheduleMaintenance() {
        maintenanceTask?.cancel()

        maintenanceTask = Task { [weak self] in
            guard let self else { return }

            // Avoid contending with startup hydration and visible panel work.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard Task.isCancelled == false else { return }

            // 长生命周期菜单栏应用，会被用户保持开启数天甚至数周。原实现只在
            // 启动后 10s 跑一次清理任务就退出，意味着这段时间里过期记录会一直
            // 累积。改为"24h 复检 + 每次读最新 retention 偏好"的常驻循环，
            // 但读偏好/做清理之前依然让步给同步任务和可见面板。
            while Task.isCancelled == false {
                while self.isSyncing || ClipboardPanelManager.shared.isVisible {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard Task.isCancelled == false else { return }
                }

                let retentionRaw = self.defaults.string(forKey: "historyRetention") ?? HistoryRetention.oneMonth.rawValue
                if let retention = HistoryRetention(rawValue: retentionRaw),
                   let expirationDate = retention.expirationDate {
                    StorageManager.shared.performAutoCleanup(before: expirationDate)
                }

                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
            }
        }
    }

}
