import Combine
import CloudKit
import Foundation
import SwiftData

enum ClipboardSyncDiagnosticLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct ClipboardSyncDiagnosticEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: ClipboardSyncDiagnosticLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ClipboardSyncDiagnosticLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

struct ClipboardSyncDiagnosticsSnapshot: Sendable {
    let activeRoute: String
    let preferredSyncEnabled: Bool
    let currentSyncEnabled: Bool
    let pendingSyncEnabled: Bool?
    let isSyncing: Bool
    let localRuntimeReady: Bool
    let cloudRuntimeReady: Bool
    let localStorePath: String
    let cloudStorePath: String
    let runtimeGeneration: String
    let lastSyncDate: Date?
    let lastError: String?
}

@MainActor
final class ClipboardRuntimeStore: ObservableObject {
    static let shared = ClipboardRuntimeStore()

    @Published private(set) var container: ModelContainer
    @Published private(set) var isSyncEnabled: Bool
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var syncError: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var runtimeGeneration: UUID
    @Published private(set) var diagnosticsEntries: [ClipboardSyncDiagnosticEntry]

    private let defaults: UserDefaults
    private let containerFactory: ClipboardModelContainerFactory
    private let bootstrapper: ClipboardStoreBootstrapper
    private let maxDiagnosticEntries = 40
    private var localRuntime: ClipboardRuntime?
    private var cloudRuntime: ClipboardRuntime?
    private var currentRuntime: ClipboardRuntime
    private var pendingSyncEnabled: Bool?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.containerFactory = .shared
        self.bootstrapper = ClipboardStoreBootstrapper()

        let preferredSyncEnabled = defaults.bool(forKey: Keys.syncEnabled)
        self.lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        self.runtimeGeneration = UUID()
        self.diagnosticsEntries = []
        self.localRuntime = nil
        self.cloudRuntime = nil
        self.pendingSyncEnabled = nil

        var resolvedSyncEnabled = preferredSyncEnabled
        var initialSyncError: String?
        var initialDiagnostics: [ClipboardSyncDiagnosticEntry] = []
        let runtime: ClipboardRuntime
        var initialLocalRuntime: ClipboardRuntime?
        var initialCloudRuntime: ClipboardRuntime?

        do {
            runtime = try containerFactory.makeRuntime(syncEnabled: preferredSyncEnabled)
            if preferredSyncEnabled {
                initialCloudRuntime = runtime
            } else {
                initialLocalRuntime = runtime
            }
            initialDiagnostics.append(
                ClipboardSyncDiagnosticEntry(
                    level: .info,
                    message: "初始化运行时成功，默认路由：\(preferredSyncEnabled ? "cloud" : "local")"
                )
            )
        } catch {
            guard preferredSyncEnabled else {
                fatalError("Failed to initialize clipboard runtime: \(error)")
            }

            let cloudError = error

            do {
                runtime = try containerFactory.makeRuntime(syncEnabled: false)
                resolvedSyncEnabled = false
                initialLocalRuntime = runtime
                initialSyncError = """
                iCloud 同步初始化失败，已自动回退到本地存储。\
                \(CloudSyncErrorFormatter.message(for: cloudError))
                """
                initialDiagnostics.append(
                    ClipboardSyncDiagnosticEntry(
                        level: .error,
                        message: "默认云路由初始化失败，已回退到本地：\(CloudSyncErrorFormatter.message(for: cloudError))"
                    )
                )
                defaults.set(false, forKey: Keys.syncEnabled)
            } catch {
                fatalError(
                    "Failed to initialize clipboard runtime. Cloud error: \(cloudError). Local fallback error: \(error)"
                )
            }
        }

        self.isSyncEnabled = resolvedSyncEnabled
        self.localRuntime = initialLocalRuntime
        self.cloudRuntime = initialCloudRuntime
        self.currentRuntime = runtime
        self.container = runtime.container
        self.diagnosticsEntries = initialDiagnostics
        self.syncError = initialSyncError
        ClipboardStorageRegistry.update(storage: runtime.storage)
        appendDiagnostic(
            level: .info,
            message: "当前激活路由：\(resolvedSyncEnabled ? "cloud" : "local")，generation=\(runtimeGeneration.uuidString)"
        )

        ClipboardMonitor.shared.startMonitoring()
        scheduleMaintenance()

        Task {
            await performInitialBootstrap()
        }
    }

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
            appendDiagnostic(level: .info, message: "忽略重复的同步开关请求：\(enabled ? "开启" : "关闭")")
            return
        }

        if isSyncing {
            pendingSyncEnabled = enabled
            appendDiagnostic(level: .warning, message: "同步切换进行中，已排队请求：\(enabled ? "开启" : "关闭")")
            return
        }

        appendDiagnostic(level: .info, message: "收到同步切换请求：\(enabled ? "开启 iCloud" : "关闭 iCloud")")
        Task {
            await rebuildRuntime(syncEnabled: enabled, mergeCurrentStore: true)
        }
    }

    func refreshCurrentRoute() {
        appendDiagnostic(level: .info, message: "收到同步状态刷新请求，当前路由：\(isSyncEnabled ? "cloud" : "local")")
        Task {
            await refreshSyncStatus()
        }
    }

    func diagnosticsReport() -> String {
        let snapshot = diagnosticsSnapshot
        let reportDate = Date().formatted(date: .numeric, time: .standard)
        let entries = diagnosticsEntries.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.level.rawValue)] \($0.message)"
        }.joined(separator: "\n")

        return """
        Clipaste Sync Diagnostics
        Generated: \(reportDate)
        Active Route: \(snapshot.activeRoute)
        Preferred Sync Enabled: \(snapshot.preferredSyncEnabled)
        Current Sync Enabled: \(snapshot.currentSyncEnabled)
        Pending Sync Request: \(snapshot.pendingSyncEnabled.map(String.init(describing:)) ?? "none")
        Is Syncing: \(snapshot.isSyncing)
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

    private func performInitialBootstrap() async {
        isSyncing = true
        syncError = nil
        appendDiagnostic(level: .info, message: "开始执行启动期旧库导入检查")

        do {
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
            appendDiagnostic(level: .info, message: "启动期旧库导入检查完成")
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(level: .error, message: "启动期旧库导入失败：\(message)")
        }

        isSyncing = false
        processPendingSyncRequestIfNeeded()
    }

    private func rebuildRuntime(syncEnabled: Bool, mergeCurrentStore: Bool) async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        ClipboardMonitor.shared.stopMonitoring()
        appendDiagnostic(
            level: .info,
            message: "开始重建运行时，目标路由：\(syncEnabled ? "cloud" : "local")，mergeCurrentStore=\(mergeCurrentStore)"
        )

        do {
            let sourceRuntime = currentRuntime
            let targetRuntime: ClipboardRuntime
            let shouldMergeStores = mergeCurrentStore && sourceRuntime.syncEnabled != syncEnabled
            let exportPayload = shouldMergeStores ? await sourceRuntime.storage.exportStore() : nil
            appendDiagnostic(
                level: .info,
                message: "当前路由：\(sourceRuntime.syncEnabled ? "cloud" : "local")，是否执行跨路由合并：\(shouldMergeStores)"
            )

            if syncEnabled {
                try await CloudSyncAvailabilityService.preflight(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                appendDiagnostic(level: .info, message: "iCloud 账户预检通过")
            }

            targetRuntime = try runtime(for: syncEnabled)
            appendDiagnostic(level: .info, message: "目标 runtime 已就绪：\(syncEnabled ? "cloud" : "local")")

            if let exportPayload {
                try await targetRuntime.storage.importStoreExport(exportPayload)
                appendDiagnostic(level: .info, message: "跨路由数据合并完成，records=\(exportPayload.records.count)，groups=\(exportPayload.groups.count)")
            }

            try await bootstrapper.importLegacyStoreIfNeeded(into: targetRuntime.storage)

            activateRuntime(
                targetRuntime,
                syncEnabled: syncEnabled,
                persistPreference: true,
                updateLastSyncDate: true
            )
            appendDiagnostic(level: .info, message: "运行时切换完成，当前路由：\(syncEnabled ? "cloud" : "local")")
            scheduleMaintenance()
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(level: .error, message: "运行时切换失败：\(message)")

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

    private func refreshSyncStatus() async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        appendDiagnostic(level: .info, message: "开始刷新同步状态，当前路由：\(currentRuntime.syncEnabled ? "cloud" : "local")")

        defer {
            isSyncing = false
            processPendingSyncRequestIfNeeded()
        }

        guard currentRuntime.syncEnabled else {
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
            appendDiagnostic(level: .info, message: "当前为本地路由，刷新操作仅更新时间戳")
            return
        }

        do {
            try await CloudSyncAvailabilityService.preflight(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            appendDiagnostic(level: .info, message: "iCloud 连接状态刷新成功")
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(level: .error, message: "同步状态刷新失败：\(message)")
        }
    }

    private func activateRuntime(
        _ runtime: ClipboardRuntime,
        syncEnabled: Bool,
        persistPreference: Bool,
        updateLastSyncDate: Bool
    ) {
        currentRuntime = runtime
        container = runtime.container
        isSyncEnabled = syncEnabled
        runtimeGeneration = UUID()

        if updateLastSyncDate {
            lastSyncDate = Date()
        }

        if persistPreference {
            defaults.set(syncEnabled, forKey: Keys.syncEnabled)
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
        }

        ClipboardStorageRegistry.update(storage: runtime.storage)
        ClipboardImagePipeline.shared.invalidateAll()
        NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        appendDiagnostic(
            level: .info,
            message: "激活 runtime：route=\(syncEnabled ? "cloud" : "local") generation=\(runtimeGeneration.uuidString)"
        )
    }

    private func runtime(for syncEnabled: Bool) throws -> ClipboardRuntime {
        if syncEnabled {
            if let cloudRuntime {
                appendDiagnostic(level: .info, message: "复用已缓存的 cloud runtime")
                return cloudRuntime
            }

            let runtime = try containerFactory.makeRuntime(syncEnabled: true)
            cloudRuntime = runtime
            appendDiagnostic(level: .info, message: "创建新的 cloud runtime")
            return runtime
        }

        if let localRuntime {
            appendDiagnostic(level: .info, message: "复用已缓存的 local runtime")
            return localRuntime
        }

        let runtime = try containerFactory.makeRuntime(syncEnabled: false)
        localRuntime = runtime
        appendDiagnostic(level: .info, message: "创建新的 local runtime")
        return runtime
    }

    private func processPendingSyncRequestIfNeeded() {
        guard let pendingSyncEnabled else { return }
        self.pendingSyncEnabled = nil

        guard pendingSyncEnabled != isSyncEnabled else { return }
        appendDiagnostic(level: .info, message: "开始执行排队中的同步请求：\(pendingSyncEnabled ? "开启" : "关闭")")

        Task {
            await rebuildRuntime(syncEnabled: pendingSyncEnabled, mergeCurrentStore: true)
        }
    }

    private func scheduleMaintenance() {
        let retentionRaw = defaults.string(forKey: "historyRetention") ?? HistoryRetention.oneMonth.rawValue
        guard let retention = HistoryRetention(rawValue: retentionRaw),
              let expirationDate = retention.expirationDate else {
            return
        }

        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            StorageManager.shared.performAutoCleanup(before: expirationDate)
        }
    }

    private func appendDiagnostic(level: ClipboardSyncDiagnosticLevel, message: String) {
        diagnosticsEntries.insert(
            ClipboardSyncDiagnosticEntry(level: level, message: message),
            at: 0
        )

        if diagnosticsEntries.count > maxDiagnosticEntries {
            diagnosticsEntries.removeLast(diagnosticsEntries.count - maxDiagnosticEntries)
        }
    }
}

private final class ClipboardStorageBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var currentStorage: StorageManager?

    nonisolated func update(storage: StorageManager) {
        lock.lock()
        currentStorage = storage
        lock.unlock()
    }

    nonisolated func storage() -> StorageManager {
        lock.lock()
        defer { lock.unlock() }

        guard let currentStorage else {
            fatalError("Clipboard storage runtime has not been configured.")
        }

        return currentStorage
    }
}

enum ClipboardStorageRegistry {
    nonisolated private static let box = ClipboardStorageBox()

    nonisolated static func update(storage: StorageManager) {
        box.update(storage: storage)
    }

    nonisolated static func storage() -> StorageManager {
        box.storage()
    }
}

private enum CloudSyncPreflightError: LocalizedError {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case cloudKit(CKError)
    case other(Error)

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "当前 Mac 未登录 iCloud。请先在系统设置中登录 Apple ID 后再开启同步。"
        case .restricted:
            return "当前设备不允许使用 iCloud。请检查系统限制或企业设备策略。"
        case .temporarilyUnavailable:
            return "iCloud 当前暂时不可用，请稍后再试。"
        case .couldNotDetermine:
            return "暂时无法确认 iCloud 账户状态，请稍后再试。"
        case let .cloudKit(error):
            return "CloudKit 账户检查失败：\(error.localizedDescription)"
        case let .other(error):
            return error.localizedDescription
        }
    }
}

private enum CloudSyncAvailabilityService {
    static func preflight(containerIdentifier: String) async throws {
        let container = CKContainer(identifier: containerIdentifier)

        do {
            let accountStatus = try await fetchAccountStatus(from: container)

            switch accountStatus {
            case .available:
                return
            case .noAccount:
                throw CloudSyncPreflightError.noAccount
            case .restricted:
                throw CloudSyncPreflightError.restricted
            case .temporarilyUnavailable:
                throw CloudSyncPreflightError.temporarilyUnavailable
            case .couldNotDetermine:
                throw CloudSyncPreflightError.couldNotDetermine
            @unknown default:
                throw CloudSyncPreflightError.couldNotDetermine
            }
        } catch let error as CKError {
            throw CloudSyncPreflightError.cloudKit(error)
        } catch let error as CloudSyncPreflightError {
            throw error
        } catch {
            throw CloudSyncPreflightError.other(error)
        }
    }

    private static func fetchAccountStatus(from container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

private enum CloudSyncErrorFormatter {
    static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           description.isEmpty == false {
            return description
        }

        let nsError = error as NSError
        var segments = [nsError.localizedDescription]

        if let failureReason = nsError.localizedFailureReason,
           failureReason.isEmpty == false,
           segments.contains(failureReason) == false {
            segments.append(failureReason)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let underlyingMessage = "底层错误：\(underlyingError.localizedDescription)"
            if segments.contains(underlyingMessage) == false {
                segments.append(underlyingMessage)
            }
        }

        if let detailedErrors = nsError.userInfo["NSDetailedErrors"] as? [NSError],
           detailedErrors.isEmpty == false {
            let detailMessage = detailedErrors
                .map { $0.localizedDescription }
                .filter { $0.isEmpty == false }
                .joined(separator: "；")

            if detailMessage.isEmpty == false {
                segments.append("详细信息：\(detailMessage)")
            }
        }

        return segments.joined(separator: " ")
    }
}

private extension ClipboardRuntimeStore {
    enum Keys {
        static let syncEnabled = "enable_icloud_sync"
        static let lastSyncDate = "last_sync_date"
    }
}
