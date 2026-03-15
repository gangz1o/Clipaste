import Combine
import CloudKit
import Foundation
import SwiftData

@MainActor
final class ClipboardRuntimeStore: ObservableObject {
    static let shared = ClipboardRuntimeStore()

    @Published private(set) var container: ModelContainer
    @Published private(set) var isSyncEnabled: Bool
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var syncError: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var runtimeGeneration: UUID

    private let defaults: UserDefaults
    private let containerFactory: ClipboardModelContainerFactory
    private let bootstrapper: ClipboardStoreBootstrapper
    private var currentRuntime: ClipboardRuntime

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.containerFactory = .shared
        self.bootstrapper = ClipboardStoreBootstrapper()

        let preferredSyncEnabled = defaults.bool(forKey: Keys.syncEnabled)
        self.lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        self.runtimeGeneration = UUID()

        var resolvedSyncEnabled = preferredSyncEnabled
        var initialSyncError: String?
        let runtime: ClipboardRuntime

        do {
            runtime = try containerFactory.makeRuntime(syncEnabled: preferredSyncEnabled)
        } catch {
            guard preferredSyncEnabled else {
                fatalError("Failed to initialize clipboard runtime: \(error)")
            }

            let cloudError = error

            do {
                runtime = try containerFactory.makeRuntime(syncEnabled: false)
                resolvedSyncEnabled = false
                initialSyncError = """
                iCloud 同步初始化失败，已自动回退到本地存储。\
                \(CloudSyncErrorFormatter.message(for: cloudError))
                """
                defaults.set(false, forKey: Keys.syncEnabled)
            } catch {
                fatalError(
                    "Failed to initialize clipboard runtime. Cloud error: \(cloudError). Local fallback error: \(error)"
                )
            }
        }

        self.isSyncEnabled = resolvedSyncEnabled
        self.currentRuntime = runtime
        self.container = runtime.container
        self.syncError = initialSyncError
        ClipboardStorageRegistry.update(storage: runtime.storage)

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

    func setSyncEnabled(_ enabled: Bool) {
        guard enabled != isSyncEnabled else { return }

        Task {
            await rebuildRuntime(syncEnabled: enabled, mergeCurrentStore: true)
        }
    }

    func refreshCurrentRoute() {
        Task {
            await rebuildRuntime(syncEnabled: isSyncEnabled, mergeCurrentStore: false)
        }
    }

    private func performInitialBootstrap() async {
        isSyncing = true
        syncError = nil

        do {
            try await bootstrapper.importLegacyStoreIfNeeded(into: currentRuntime.storage)
            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        } catch {
            syncError = CloudSyncErrorFormatter.message(for: error)
        }

        isSyncing = false
    }

    private func rebuildRuntime(syncEnabled: Bool, mergeCurrentStore: Bool) async {
        guard isSyncing == false else { return }

        isSyncing = true
        syncError = nil
        ClipboardMonitor.shared.stopMonitoring()

        do {
            if syncEnabled {
                try await CloudSyncAvailabilityService.preflight(
                    containerIdentifier: ClipboardModelContainerFactory.cloudKitContainerIdentifier
                )
            }

            let sourceStorage = currentRuntime.storage
            let nextRuntime = try containerFactory.makeRuntime(syncEnabled: syncEnabled)

            if mergeCurrentStore {
                try await bootstrapper.merge(from: sourceStorage, to: nextRuntime.storage)
            }

            try await bootstrapper.importLegacyStoreIfNeeded(into: nextRuntime.storage)

            currentRuntime = nextRuntime
            container = nextRuntime.container
            isSyncEnabled = syncEnabled
            runtimeGeneration = UUID()
            lastSyncDate = Date()

            defaults.set(syncEnabled, forKey: Keys.syncEnabled)
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)

            ClipboardStorageRegistry.update(storage: nextRuntime.storage)
            ClipboardImagePipeline.shared.invalidateAll()
            scheduleMaintenance()

            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        } catch {
            syncError = CloudSyncErrorFormatter.message(for: error)
        }

        ClipboardMonitor.shared.startMonitoring()
        isSyncing = false
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
