import Foundation
import SwiftUI
import Combine

// 管理 iCloud 同步状态的独立业务层
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @AppStorage("enable_icloud_sync") var isSyncEnabled: Bool = false {
        didSet {
            handleSyncStateChange(enabled: isSyncEnabled)
        }
    }

    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var syncError: String? = nil

    private init() {
        // 初始化时加载最后同步时间
        self.lastSyncDate = UserDefaults.standard.object(forKey: "last_sync_date") as? Date
    }

    // MARK: - Public

    func forceSync() {
        guard isSyncEnabled else { return }
        startSync()
    }

    // MARK: - Private

    /// 隔离具体的底层同步触发逻辑 (供后续接入 SwiftData/CoreData 的 CloudKit 引擎)
    private func handleSyncStateChange(enabled: Bool) {
        if enabled {
            startSync()
        } else {
            stopSync()
        }
    }

    private func startSync() {
        isSyncing = true
        syncError = nil

        // 占位：实际的 CloudKit/SwiftData 同步逻辑将在这里执行
        // 模拟网络请求后的状态更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isSyncing = false
            let now = Date()
            self?.lastSyncDate = now
            UserDefaults.standard.set(now, forKey: "last_sync_date")
        }
    }

    private func stopSync() {
        // 占位：关闭底层容器同步的逻辑
        isSyncing = false
    }
}
