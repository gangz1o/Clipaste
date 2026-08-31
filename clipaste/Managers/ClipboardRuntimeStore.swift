import CloudKit
import CoreData
import Foundation
import os
import SwiftData

@MainActor
@Observable
final class ClipboardRuntimeStore {
    static let shared = ClipboardRuntimeStore()

    var container: ModelContainer
    var isSyncEnabled: Bool
    var isSyncing: Bool = false
    var syncError: String?
    var lastSyncDate: Date?
    var runtimeGeneration: UUID
    // ⚠️ 性能边界：以下几个字段在 sync 活跃时高频变化（每条 diagnostic、每次
    // CloudKit 拉取都会写入），但只用于 `diagnosticsSnapshot` / `diagnosticsReport`
    // 拼字符串，没有任何 SwiftUI 视图直接读取。用 @ObservationIgnored 把它们
    // 从 @Observable 的追踪图里摘出去，避免无意义的 view invalidation 广播。
    @ObservationIgnored
    var diagnosticsEntries: [ClipboardSyncDiagnosticEntry]
    @ObservationIgnored
    var cloudKitAccountRecordName: String?
    @ObservationIgnored
    var cloudStoreDiagnostics: ClipboardStoreDiagnosticsSnapshot?
    @ObservationIgnored
    var cloudServerDiagnostics: CloudKitServerDiagnosticsSnapshot?
    @ObservationIgnored
    var cloudServerDiagnosticsError: String?

    let defaults: UserDefaults
    let containerFactory: ClipboardModelContainerFactory
    let bootstrapper: ClipboardStoreBootstrapper
    let maxDiagnosticEntries = 40
    var localRuntime: ClipboardRuntime?
    var cloudRuntime: ClipboardRuntime?
    var currentRuntime: ClipboardRuntime
    var pendingSyncEnabled: Bool?
    var maintenanceTask: Task<Void, Never>?
    var remoteStoreObserver: NSObjectProtocol?
    var cloudKitEventObserver: NSObjectProtocol?
    var remoteRepairTask: Task<Void, Never>?
    var clipboardSnapshotSignature: String?
    var lastDuplicateRepairDate: Date?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.containerFactory = .shared
        self.bootstrapper = ClipboardStoreBootstrapper()

        let preferredSyncEnabled = defaults.bool(forKey: Keys.syncEnabled)
        self.lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        self.runtimeGeneration = UUID()
        self.diagnosticsEntries = []
        self.cloudKitAccountRecordName = nil
        self.cloudStoreDiagnostics = nil
        self.cloudServerDiagnostics = nil
        self.cloudServerDiagnosticsError = nil
        self.localRuntime = nil
        self.cloudRuntime = nil
        self.pendingSyncEnabled = nil

        var resolvedSyncEnabled = preferredSyncEnabled
        var initialSyncError: String?
        var initialDiagnostics: [ClipboardSyncDiagnosticEntry] = []
        let runtime: ClipboardRuntime
        var initialLocalRuntime: ClipboardRuntime?
        var initialCloudRuntime: ClipboardRuntime?
        let bootstrapContainerFactory = self.containerFactory

        do {
            let resolution = try ClipboardRuntimeBootstrapPolicy.resolve(
                preferredSyncEnabled: preferredSyncEnabled,
                makePersistentRuntime: { try bootstrapContainerFactory.makeRuntime(syncEnabled: $0) },
                makeInMemoryRuntime: { try bootstrapContainerFactory.makeInMemoryRuntime() }
            )
            runtime = resolution.value

            switch resolution.source {
            case .preferred:
                if preferredSyncEnabled {
                    initialCloudRuntime = runtime
                } else {
                    initialLocalRuntime = runtime
                }
                initialDiagnostics.append(
                    ClipboardSyncDiagnosticEntry(
                        level: .info,
                        message: ClipboardSyncDiagnosticMessage(
                            "Initialized runtime successfully. Default route: %@",
                            arguments: [.route(preferredSyncEnabled ? "cloud" : "local")]
                        )
                    )
                )

            case .localFallback:
                let preferredRouteError = resolution.preferredError
                    ?? ClipboardRuntimeBootstrapFailure(
                        persistentError: CocoaError(.fileReadUnknown),
                        memoryError: CocoaError(.fileReadUnknown)
                    )
                resolvedSyncEnabled = false
                initialLocalRuntime = runtime
                initialSyncError = """
                iCloud 同步初始化失败，已自动回退到本地存储。\
                \(CloudSyncErrorFormatter.message(for: preferredRouteError))
                """
                initialDiagnostics.append(
                    ClipboardSyncDiagnosticEntry(
                        level: .error,
                        message: ClipboardSyncDiagnosticMessage(
                            "Default iCloud route failed to initialize. Fell back to local storage: %@",
                            arguments: [.string(CloudSyncErrorFormatter.message(for: preferredRouteError))]
                        )
                    )
                )

            case .memoryFallback:
                let preferredRouteError = resolution.preferredError
                    ?? ClipboardRuntimeBootstrapFailure(
                        persistentError: CocoaError(.fileReadUnknown),
                        memoryError: CocoaError(.fileReadUnknown)
                    )
                resolvedSyncEnabled = false
                initialLocalRuntime = runtime
                initialSyncError = """
                持久化剪贴板存储暂不可用，当前使用临时内存存储。退出应用前的新记录不会保留。\
                \(CloudSyncErrorFormatter.message(for: preferredRouteError))
                """
                initialDiagnostics.append(
                    ClipboardSyncDiagnosticEntry(
                        level: .error,
                        message: ClipboardSyncDiagnosticMessage(
                            "Persistent clipboard storage failed to initialize. Using temporary in-memory storage: %@",
                            arguments: [.string(CloudSyncErrorFormatter.message(for: preferredRouteError))]
                        )
                    )
                )
            }

            defaults.set(resolvedSyncEnabled, forKey: Keys.syncEnabled)
        } catch {
            preconditionFailure("Failed to initialize clipboard recovery runtime: \(error)")
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
            message: ClipboardSyncDiagnosticMessage(
                "Active route: %@, generation=%@",
                arguments: [.route(resolvedSyncEnabled ? "cloud" : "local"), .string(runtimeGeneration.uuidString)]
            )
        )
        scheduleWarmCacheRefresh(using: runtime.storage, routeKey: rootIdentity)

        ClipboardMonitor.shared.startMonitoring()

        Task {
            await performInitialBootstrap()
        }

        remoteStoreObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRemoteImportRepair()
            }
        }

        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
                Task { @MainActor [weak self] in
                    self?.scheduleRemoteImportRepair()
                }
                return
            }

            guard event.endDate != nil else { return }

            let eventType = event.type
            let errorMessage = event.error.map { CloudSyncErrorFormatter.message(for: $0) }

            Task { @MainActor [weak self] in
                guard let self else { return }

                switch eventType {
                case .import:
                    self.scheduleRemoteImportRepair()
                case .export:
                    // 导出失败以前是完全静默的:队列卡死数周用户也毫无感知。
                    // 这里把导出结果同步进 syncError / lastSyncDate,让设置页状态灯反映真实健康度。
                    self.handleExportEventCompletion(errorMessage: errorMessage)
                default:
                    break
                }
            }
        }
    }
}
