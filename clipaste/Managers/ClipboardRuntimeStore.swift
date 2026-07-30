import CloudKit
import CoreData
import Foundation
import os
import SwiftData

enum ClipboardSyncDiagnosticLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct ClipboardSyncDiagnosticMessage: Sendable {
    enum Argument: Sendable {
        case string(String)
        case route(String)
        case syncState(Bool)
        case bool(Bool)
        case count(Int)

        func localized(locale: Locale) -> String {
            switch self {
            case .string(let value):
                return value
            case .route(let route):
                let key = route == "cloud" ? "iCloud" : "Local"
                return Self.localized(key, locale: locale)
            case .syncState(let isEnabled):
                let key = isEnabled ? "On" : "Off"
                return Self.localized(key, locale: locale)
            case .bool(let value):
                let key = value ? "Yes" : "No"
                return Self.localized(key, locale: locale)
            case .count(let value):
                let formatter = NumberFormatter()
                formatter.locale = locale
                formatter.numberStyle = .decimal
                return formatter.string(from: NSNumber(value: value)) ?? String(value)
            }
        }

        private static func localized(_ key: String, locale: Locale) -> String {
            let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
            return String(localized: resource)
        }
    }

    let key: String
    let arguments: [Argument]

    init(_ key: String, arguments: [Argument] = []) {
        self.key = key
        self.arguments = arguments
    }

    func localized(locale: Locale) -> String {
        let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
        let template = String(localized: resource)
        guard arguments.isEmpty == false else { return template }

        let localizedArguments = arguments.map { $0.localized(locale: locale) }
        return String(format: template, locale: locale, arguments: localizedArguments)
    }
}

struct ClipboardSyncDiagnosticEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: ClipboardSyncDiagnosticLevel
    let message: ClipboardSyncDiagnosticMessage

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ClipboardSyncDiagnosticLevel,
        message: ClipboardSyncDiagnosticMessage
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    func localizedMessage(locale: Locale) -> String {
        message.localized(locale: locale)
    }
}

struct ClipboardSyncDiagnosticsSnapshot: Sendable {
    let activeRoute: String
    let preferredSyncEnabled: Bool
    let currentSyncEnabled: Bool
    let pendingSyncEnabled: Bool?
    let isSyncing: Bool
    let cloudKitContainerIdentifier: String
    let cloudKitEnvironment: String
    let cloudKitAccountRecordName: String?
    let cloudStoreRecordCount: Int?
    let cloudStoreGroupCount: Int?
    let cloudServerRecordCount: Int?
    let cloudServerGroupCount: Int?
    let cloudServerError: String?
    let latestRecordFingerprints: [String]
    let localRuntimeReady: Bool
    let cloudRuntimeReady: Bool
    let localStorePath: String
    let cloudStorePath: String
    let runtimeGeneration: String
    let lastSyncDate: Date?
    let lastError: String?
}

@MainActor
@Observable
final class ClipboardRuntimeStore {
    static let shared = ClipboardRuntimeStore()

    private(set) var container: ModelContainer
    private(set) var isSyncEnabled: Bool
    private(set) var isSyncing: Bool = false
    private(set) var syncError: String?
    private(set) var lastSyncDate: Date?
    private(set) var runtimeGeneration: UUID
    // ⚠️ 性能边界：以下几个字段在 sync 活跃时高频变化（每条 diagnostic、每次
    // CloudKit 拉取都会写入），但只用于 `diagnosticsSnapshot` / `diagnosticsReport`
    // 拼字符串，没有任何 SwiftUI 视图直接读取。用 @ObservationIgnored 把它们
    // 从 @Observable 的追踪图里摘出去，避免无意义的 view invalidation 广播。
    @ObservationIgnored
    private(set) var diagnosticsEntries: [ClipboardSyncDiagnosticEntry]
    @ObservationIgnored
    private(set) var cloudKitAccountRecordName: String?
    @ObservationIgnored
    private(set) var cloudStoreDiagnostics: ClipboardStoreDiagnosticsSnapshot?
    @ObservationIgnored
    private(set) var cloudServerDiagnostics: CloudKitServerDiagnosticsSnapshot?
    @ObservationIgnored
    private(set) var cloudServerDiagnosticsError: String?

    private let defaults: UserDefaults
    private let containerFactory: ClipboardModelContainerFactory
    private let bootstrapper: ClipboardStoreBootstrapper
    private let maxDiagnosticEntries = 40
    private var localRuntime: ClipboardRuntime?
    private var cloudRuntime: ClipboardRuntime?
    private var currentRuntime: ClipboardRuntime
    private var pendingSyncEnabled: Bool?
    private var maintenanceTask: Task<Void, Never>?
    private var remoteStoreObserver: NSObjectProtocol?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var remoteRepairTask: Task<Void, Never>?
    private var clipboardSnapshotSignature: String?
    private var lastDuplicateRepairDate: Date?

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
                    message: ClipboardSyncDiagnosticMessage(
                        "Initialized runtime successfully. Default route: %@",
                        arguments: [.route(preferredSyncEnabled ? "cloud" : "local")]
                    )
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
                        message: ClipboardSyncDiagnosticMessage(
                            "Default iCloud route failed to initialize. Fell back to local storage: %@",
                            arguments: [.string(CloudSyncErrorFormatter.message(for: cloudError))]
                        )
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
        CloudKit Account Record: \(snapshot.cloudKitAccountRecordName ?? "unknown")
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

    private func performInitialBootstrap() async {
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

    private func rebuildRuntime(syncEnabled: Bool, mergeCurrentStore: Bool) async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        ClipboardMonitor.shared.stopMonitoring()
        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Starting runtime rebuild. Target route: %@, merge current store: %@",
                arguments: [.route(syncEnabled ? "cloud" : "local"), .bool(mergeCurrentStore)]
            )
        )

        do {
            let sourceRuntime = currentRuntime
            let targetRuntime: ClipboardRuntime
            let shouldMergeStores = mergeCurrentStore && sourceRuntime.syncEnabled != syncEnabled
            let exportPayload = shouldMergeStores ? await sourceRuntime.storage.exportStore() : nil
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Current route: %@. Cross-route merge: %@",
                    arguments: [.route(sourceRuntime.syncEnabled ? "cloud" : "local"), .bool(shouldMergeStores)]
                )
            )

            if syncEnabled {
                try await CloudSyncAvailabilityService.preflight(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "iCloud account preflight passed. Account record: %@",
                        arguments: [.string(cloudKitAccountRecordName ?? "unknown")]
                    )
                )
            }

            targetRuntime = try runtime(for: syncEnabled)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Target runtime is ready: %@",
                    arguments: [.route(syncEnabled ? "cloud" : "local")]
                )
            )

            if let exportPayload {
                try await targetRuntime.storage.importStoreExport(exportPayload)
                let repairedDuplicateCount = await targetRuntime.storage.repairDuplicateRecords()
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Cross-route data merge completed. Records: %@, groups: %@",
                        arguments: [.count(exportPayload.records.count), .count(exportPayload.groups.count)]
                    )
                )
                if repairedDuplicateCount > 0 {
                    appendDiagnostic(
                        level: .info,
                        message: ClipboardSyncDiagnosticMessage(
                            "Repaired %@ duplicate synced record(s)",
                            arguments: [.count(repairedDuplicateCount)]
                        )
                    )
                }
            }

            try await bootstrapper.importLegacyStoreIfNeeded(into: targetRuntime.storage)
            let repairedDuplicateCount = await targetRuntime.storage.repairDuplicateRecords()
            if repairedDuplicateCount > 0 {
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Repaired %@ duplicate synced record(s)",
                        arguments: [.count(repairedDuplicateCount)]
                    )
                )
            }
            if syncEnabled {
                await refreshCloudStoreDiagnostics(using: targetRuntime.storage)
            }

            activateRuntime(
                targetRuntime,
                syncEnabled: syncEnabled,
                persistPreference: true,
                updateLastSyncDate: true
            )
            await resetClipboardSnapshotSignature(using: targetRuntime.storage)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Runtime switch completed. Current route: %@",
                    arguments: [.route(syncEnabled ? "cloud" : "local")]
                )
            )
            scheduleMaintenance()
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Runtime switch failed: %@",
                    arguments: [.string(message)]
                )
            )

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

    private func resetCloudLocalCacheRuntime() async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        ClipboardMonitor.shared.stopMonitoring()
        remoteRepairTask?.cancel()
        remoteRepairTask = nil

        appendDiagnostic(
            level: .warning,
            message: ClipboardSyncDiagnosticMessage("Resetting local iCloud cache. Cloud records will be kept")
        )

        do {
            try await CloudSyncAvailabilityService.preflight(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )
            cloudKitAccountRecordName = try await CloudSyncAvailabilityService.accountRecordName(
                containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
            )

            let localRuntime: ClipboardRuntime
            if let cachedLocalRuntime = self.localRuntime {
                localRuntime = cachedLocalRuntime
            } else {
                localRuntime = try await makeRuntimeOffMain(syncEnabled: false)
                self.localRuntime = localRuntime
            }

            cloudRuntime = nil
            activateRuntime(
                localRuntime,
                syncEnabled: false,
                persistPreference: false,
                updateLastSyncDate: false,
                notifyObservers: false
            )

            try await Task.detached(priority: .utility) {
                try ClipboardModelContainerFactory.resetCloudStoreArtifacts()
            }.value

            let cloudRuntime = try await makeRuntimeOffMain(syncEnabled: true)
            self.cloudRuntime = cloudRuntime
            activateRuntime(
                cloudRuntime,
                syncEnabled: true,
                persistPreference: true,
                updateLastSyncDate: true
            )

            try await cloudRuntime.storage.touchSyncAnchor()
            await refreshCloudStoreDiagnostics(using: cloudRuntime.storage)
            scheduleRemoteImportRepair()

            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("Local iCloud cache reset completed")
            )
        } catch {
            let message = CloudSyncErrorFormatter.message(for: error)
            syncError = message
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Local iCloud cache reset failed: %@",
                    arguments: [.string(message)]
                )
            )

            if currentRuntime.syncEnabled == false {
                defaults.set(false, forKey: Keys.syncEnabled)
                isSyncEnabled = false
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

    private func activateRuntime(
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

    private func runtime(for syncEnabled: Bool) throws -> ClipboardRuntime {
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

    private func makeRuntimeOffMain(syncEnabled: Bool) async throws -> ClipboardRuntime {
        let containerFactory = containerFactory
        return try await Task.detached(priority: .utility) {
            try containerFactory.makeRuntime(syncEnabled: syncEnabled)
        }.value
    }

    private func refreshCloudStoreDiagnostics(using storage: StorageManager) async {
        cloudStoreDiagnostics = await storage.diagnosticsSnapshot()
    }

    private func refreshCloudServerDiagnostics() async {
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

    private func processPendingSyncRequestIfNeeded() {
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

    private func scheduleMaintenance() {
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

    private func scheduleRemoteImportRepair() {
        remoteRepairTask?.cancel()
        remoteRepairTask = Task { [weak self] in
            guard let self else { return }

            // Single tail-pass catches CloudKit deliveries that finish a
            // short moment after eventChanged fires; the no-op signature
            // check makes this cheap when nothing actually changed.
            await self.refreshAfterRemoteImport()
            await self.refreshAfterRemoteImportPasses(delays: [1_500_000_000])
        }
    }

    private func handleExportEventCompletion(errorMessage: String?) {
        if let errorMessage {
            guard syncError != errorMessage else { return }

            syncError = errorMessage
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "iCloud export failed: %@",
                    arguments: [.string(errorMessage)]
                )
            )
            return
        }

        lastSyncDate = Date()
        defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)

        if syncError != nil {
            syncError = nil
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage("iCloud export recovered after previous failure")
            )
        }
    }

    private func nudgeCurrentRoute() async {
        guard currentRuntime.syncEnabled else { return }

        do {
            try await currentRuntime.storage.touchSyncAnchor()
            scheduleRemoteImportRepair()
        } catch {
            syncError = CloudSyncErrorFormatter.message(for: error)
            appendDiagnostic(
                level: .error,
                message: ClipboardSyncDiagnosticMessage(
                    "Sync anchor update failed: %@",
                    arguments: [.string(syncError ?? error.localizedDescription)]
                )
            )
        }
    }

    private func refreshAfterRemoteImport() async {
        // Detect actual content change first via the lightweight signature;
        // skip dedup entirely on no-op CloudKit pings. When a change is
        // observed, dedup is throttled (default: at most once per 10 min) —
        // ordinary capture-time dedup is already handled inline in upsert.
        let latestSignature = await makeClipboardSnapshotSignature(using: currentRuntime.storage)
        let didChange = updateClipboardSnapshotSignature(latestSignature)

        guard didChange else { return }

        let repairedCount = await repairDuplicateRecordsIfThrottled(using: currentRuntime.storage)
        await refreshCloudStoreDiagnostics(using: currentRuntime.storage)

        NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        scheduleWarmCacheRefresh(using: currentRuntime.storage, routeKey: rootIdentity)

        guard repairedCount > 0 else { return }

        appendDiagnostic(
            level: .info,
            message: ClipboardSyncDiagnosticMessage(
                "Repaired %@ duplicate synced record(s)",
                arguments: [.count(repairedCount)]
            )
        )
    }

    private func refreshAfterRemoteImportPasses(delays: [UInt64]) async {
        for delay in delays {
            try? await Task.sleep(nanoseconds: delay)
            guard Task.isCancelled == false else { return }
            await refreshAfterRemoteImport()
        }
    }

    private func resetClipboardSnapshotSignature(using storage: StorageManager) async {
        clipboardSnapshotSignature = await makeClipboardSnapshotSignature(using: storage)
    }

    private func updateClipboardSnapshotSignature(_ latestSignature: String) -> Bool {
        defer { clipboardSnapshotSignature = latestSignature }
        guard let clipboardSnapshotSignature else { return true }
        return clipboardSnapshotSignature != latestSignature
    }

    private func makeClipboardSnapshotSignature(using storage: StorageManager) async -> String {
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

    private func scheduleWarmCacheRefresh(using storage: StorageManager, routeKey: String) {
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

    private func repairDuplicateRecordsIfNeeded(using storage: StorageManager) async -> Int {
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

    private func recoverLocalFavoritesIfNeeded() async throws {
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

            let payload = try await sourceRuntime.storage.exportPinnedRecords()
            if payload.records.isEmpty == false {
                try await currentRuntime.storage.importStoreExport(payload)
            }

            defaults.set(FavoriteRecovery.currentVersion, forKey: Keys.favoriteRecoveryVersion)
            appendDiagnostic(
                level: .info,
                message: ClipboardSyncDiagnosticMessage(
                    "Local favorite recovery completed. Records: %@, groups: %@",
                    arguments: [.count(payload.records.count), .count(payload.groups.count)]
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

    private func repairDuplicateRecordsIfThrottled(using storage: StorageManager) async -> Int {
        if let lastDuplicateRepairDate,
           Date().timeIntervalSince(lastDuplicateRepairDate) < DedupThrottle.minimumInterval {
            return 0
        }

        let repairedCount = await storage.repairDuplicateRecords()
        lastDuplicateRepairDate = Date()
        return repairedCount
    }

    private func repairOversizedTextRecordsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = 1
        let storedVersion = defaults.integer(forKey: Keys.oversizedTextRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let repairedCount = await storage.repairOversizedInlineTextRecords()
        defaults.set(currentVersion, forKey: Keys.oversizedTextRepairVersion)
        return repairedCount
    }

    private func repairTextClassificationsIfNeeded(using storage: StorageManager) async -> Int {
        let currentVersion = ClipboardContentClassifier.repairVersion
        let storedVersion = defaults.integer(forKey: Keys.textClassificationRepairVersion)

        guard storedVersion < currentVersion else {
            return 0
        }

        let repairedCount = await storage.repairTextClassificationsIfNeeded()
        defaults.set(currentVersion, forKey: Keys.textClassificationRepairVersion)
        return repairedCount
    }

    private func repairAppIconColorsIfNeeded(using storage: StorageManager) async -> Int {
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

        for bundleID in bundleIDs {
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

    private func repairAppIconDataIfNeeded(using storage: StorageManager) async -> Int {
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

        for bundleID in bundleIDs {
            guard let iconData = AppIconManager.shared.iconPNGData(for: bundleID) else {
                continue
            }

            iconDataByBundleID[bundleID] = iconData
        }

        let repairedCount = await storage.repairAppIconData(using: iconDataByBundleID)
        defaults.set(currentVersion, forKey: Keys.appIconDataRepairVersion)
        return repairedCount
    }

    private func appendDiagnostic(level: ClipboardSyncDiagnosticLevel, message: ClipboardSyncDiagnosticMessage) {
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

    static func accountRecordName(containerIdentifier: String) async throws -> String {
        let container = CKContainer(identifier: containerIdentifier)
        return try await fetchUserRecordID(from: container).recordName
    }

    private static func fetchAccountStatus(from container: CKContainer) async throws -> CKAccountStatus {
        // CKContainer.accountStatus's completion handler can fire more than once
        // on some macOS versions. withCheckedThrowingContinuation traps on
        // double-resume, so we use the unsafe variant with a manual guard.
        try await withUnsafeThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            container.accountStatus { status, error in
                let alreadyResumed = resumed.withLock { flag -> Bool in
                    if flag { return true }
                    flag = true
                    return false
                }
                guard !alreadyResumed else { return }

                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private static func fetchUserRecordID(from container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: CloudSyncPreflightError.couldNotDetermine)
                }
            }
        }
    }
}

struct CloudKitServerDiagnosticsSnapshot: Sendable {
    let recordCount: Int
    let groupCount: Int
}

private enum CloudKitServerDiagnosticsService {
    private static let clipboardRecordType = "CD_ClipboardRecord"
    private static let clipboardGroupType = "CD_ClipboardGroupModel"

    static func snapshot(containerIdentifier: String) async throws -> CloudKitServerDiagnosticsSnapshot {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let counts = try await countRecords(database: database)

        return CloudKitServerDiagnosticsSnapshot(
            recordCount: counts.records,
            groupCount: counts.groups
        )
    }

    private static func countRecords(database: CKDatabase) async throws -> (records: Int, groups: Int) {
        let zoneIDs = try await fetchRecordZoneIDs(database: database)
        var recordCount = 0
        var groupCount = 0

        for zoneID in zoneIDs {
            let zoneCounts = try await countRecords(in: zoneID, database: database)
            recordCount += zoneCounts.records
            groupCount += zoneCounts.groups
        }

        return (recordCount, groupCount)
    }

    private static func countRecords(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> (records: Int, groups: Int) {
        if zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
            do {
                let records = try await countQueryRecords(ofType: clipboardRecordType, in: zoneID, database: database)
                let groups = try await countQueryRecords(ofType: clipboardGroupType, in: zoneID, database: database)
                return (records, groups)
            } catch {
                return (0, 0)
            }
        }

        return try await countChangedRecords(in: zoneID, database: database)
    }

    private static func countQueryRecords(
        ofType recordType: String,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let firstPage = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: [],
            resultsLimit: 200
        )
        var count = successfulRecordCount(firstPage.matchResults)
        var cursor = firstPage.queryCursor

        while let currentCursor = cursor {
            let page = try await database.records(
                continuingMatchFrom: currentCursor,
                desiredKeys: [],
                resultsLimit: 200
            )
            count += successfulRecordCount(page.matchResults)
            cursor = page.queryCursor
        }

        return count
    }

    private static func countChangedRecords(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> (records: Int, groups: Int) {
        var recordCount = 0
        var groupCount = 0
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                desiredKeys: [],
                resultsLimit: nil
            )

            for result in changes.modificationResultsByID.values {
                guard case let .success(modification) = result else { continue }
                switch modification.record.recordType {
                case clipboardRecordType:
                    recordCount += 1
                case clipboardGroupType:
                    groupCount += 1
                default:
                    break
                }
            }

            changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        return (recordCount, groupCount)
    }

    private static func successfulRecordCount(
        _ results: [(CKRecord.ID, Result<CKRecord, Error>)]
    ) -> Int {
        results.reduce(0) { count, result in
            guard case .success = result.1 else { return count }
            return count + 1
        }
    }

    private static func fetchRecordZoneIDs(database: CKDatabase) async throws -> [CKRecordZone.ID] {
        var zoneIDs: Set<CKRecordZone.ID> = [CKRecordZone.default().zoneID]
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let changes = try await database.databaseChanges(since: changeToken, resultsLimit: nil)
            for modification in changes.modifications {
                zoneIDs.insert(modification.zoneID)
            }
            changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        return Array(zoneIDs)
    }
}

private enum CloudSyncErrorFormatter {
    static func message(for error: Error) -> String {
        // CKError.partialFailure 的顶层描述只有一句 "Failed to modify some records",
        // 真正的失败原因(记录过大、配额不足等)藏在 per-item 错误里,展开它。
        if let ckError = error as? CKError,
           ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID,
           partialErrors.isEmpty == false {
            let distinctReasons = Set(partialErrors.values.map { ($0 as NSError).localizedDescription })
            let detail = distinctReasons.sorted().prefix(3).joined(separator: "；")
            return "CloudKit 部分记录同步失败（\(partialErrors.count) 条）：\(detail)"
        }

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
        static let textClassificationRepairVersion = "clipboard_text_classification_repair_version"
        static let appIconColorRepairVersion = "clipboard_app_icon_color_repair_version"
        static let appIconDataRepairVersion = "clipboard_app_icon_data_repair_version"
        static let duplicateRepairVersion = "clipboard_duplicate_repair_version"
        static let oversizedTextRepairVersion = "clipboard_oversized_text_repair_version"
        static let favoriteRecoveryVersion = "clipboard_favorite_cloud_recovery_version"
    }

    enum FavoriteRecovery {
        static let currentVersion = 1
    }

    enum DedupThrottle {
        // Dedup is O(n) over the full record table. Only run it occasionally
        // after CloudKit deliveries — most CloudKit events do not actually
        // introduce duplicates, and our inline upsert path already handles
        // ordinary capture-time duplicates.
        static let minimumInterval: TimeInterval = 10 * 60
        // Version bumps force a one-shot dedup on next startup.
        static let currentVersion = 1
    }
}
