import Combine
import CloudKit
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
    private var maintenanceTask: Task<Void, Never>?

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
            let repairedCount = await currentRuntime.storage.repairImportedMigrationTimestampsIfNeeded()
            let repairedClassificationCount = await repairTextClassificationsIfNeeded(using: currentRuntime.storage)
            let repairedAppIconColorCount = await repairAppIconColorsIfNeeded(using: currentRuntime.storage)
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
                    "Startup legacy-store import failed: %@",
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
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage("iCloud account preflight passed")
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
                appendDiagnostic(
                    level: .info,
                    message: ClipboardSyncDiagnosticMessage(
                        "Cross-route data merge completed. Records: %@, groups: %@",
                        arguments: [.count(exportPayload.records.count), .count(exportPayload.groups.count)]
                    )
                )
            }

            try await bootstrapper.importLegacyStoreIfNeeded(into: targetRuntime.storage)

            activateRuntime(
                targetRuntime,
                syncEnabled: syncEnabled,
                persistPreference: true,
                updateLastSyncDate: true
            )
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
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
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
        scheduleWarmCacheRefresh(using: runtime.storage, routeKey: rootIdentity)
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

        let retentionRaw = defaults.string(forKey: "historyRetention") ?? HistoryRetention.oneMonth.rawValue
        guard let retention = HistoryRetention(rawValue: retentionRaw),
              let expirationDate = retention.expirationDate else {
            return
        }

        maintenanceTask = Task { [weak self] in
            guard let self else { return }

            // Avoid contending with startup hydration and visible panel work.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard Task.isCancelled == false else { return }

            while self.isSyncing || ClipboardPanelManager.shared.isVisible {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard Task.isCancelled == false else { return }
            }

            StorageManager.shared.performAutoCleanup(before: expirationDate)
        }
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
        static let textClassificationRepairVersion = "clipboard_text_classification_repair_version"
        static let appIconColorRepairVersion = "clipboard_app_icon_color_repair_version"
    }
}
