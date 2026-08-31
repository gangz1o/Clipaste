import AppKit
import Foundation
import os

@MainActor
final class ClipboardMonitor: ClipboardCaptureDraining {
    static let shared = ClipboardMonitor()
    nonisolated static let resourceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clipaste",
        category: "ClipboardResourcePolicy"
    )

    let pasteboard = NSPasteboard.general
    let defaults: UserDefaults
    var lastChangeCount: Int = 0
    var monitoringTask: Task<Void, Never>?
    var persistenceTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) var defaultsObserver: NSObjectProtocol?
    let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    let utf8PlainTextType = NSPasteboard.PasteboardType("public.utf8-plain-text")
    var isMonitoringLifecycleActive = false
    var isMonitoringPaused = false
    var pollingInterval: TimeInterval
    var ignoredBundleIdentifiers: Set<String>
    let captureSessionID = UUID()
    var isIgnoredNextChange: Bool = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isMonitoringPaused = defaults.bool(forKey: Keys.isMonitoringPaused)
        self.pollingInterval = Self.sanitizedPollingInterval(
            defaults.object(forKey: Keys.monitorInterval) as? Double
        )
        self.ignoredBundleIdentifiers = IgnoredAppsService.ignoredBundleIdentifierSet(defaults: defaults)
        observePreferences()
    }

    deinit {
        monitoringTask?.cancel()
        for task in persistenceTasks.values {
            task.cancel()
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func startMonitoring() {
        isMonitoringLifecycleActive = true
        refreshMonitoringLoop(resetChangeBaseline: true)
    }

    func stopMonitoring() {
        isMonitoringLifecycleActive = false
        cancelMonitoringLoop()
    }

    func stopMonitoringAndDrain() async {
        stopMonitoring()
        let tasks = persistenceTasks
        for (id, task) in tasks {
            await task.value
            persistenceTasks.removeValue(forKey: id)
        }
    }

    private func observePreferences() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyPersistedPreferences()
            }
        }
    }

    private func applyPersistedPreferences() {
        let persistedPauseState = defaults.bool(forKey: Keys.isMonitoringPaused)
        let persistedInterval = Self.sanitizedPollingInterval(
            defaults.object(forKey: Keys.monitorInterval) as? Double
        )
        let persistedIgnoredBundleIdentifiers = IgnoredAppsService.ignoredBundleIdentifierSet(defaults: defaults)

        let pauseStateChanged = persistedPauseState != isMonitoringPaused
        let intervalChanged = persistedInterval != pollingInterval
        let ignoredAppsChanged = persistedIgnoredBundleIdentifiers != ignoredBundleIdentifiers

        guard pauseStateChanged || intervalChanged || ignoredAppsChanged else { return }

        isMonitoringPaused = persistedPauseState
        pollingInterval = persistedInterval
        ignoredBundleIdentifiers = persistedIgnoredBundleIdentifiers

        // Resume 时需要丢弃暂停期间的剪贴板变化，避免把“暂停期间产生的最新剪贴板”补录进历史。
        let shouldResetBaseline = pauseStateChanged && persistedPauseState == false
        refreshMonitoringLoop(resetChangeBaseline: shouldResetBaseline)
    }

    private func refreshMonitoringLoop(resetChangeBaseline: Bool) {
        if resetChangeBaseline {
            lastChangeCount = pasteboard.changeCount
            isIgnoredNextChange = false
        }

        let shouldMonitor = isMonitoringLifecycleActive && !isMonitoringPaused
        guard shouldMonitor else {
            cancelMonitoringLoop()
            return
        }

        let intervalNanoseconds = Self.nanoseconds(for: pollingInterval)
        cancelMonitoringLoop()

        monitoringTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .nanoseconds(intervalNanoseconds))
                await self?.pollPasteboardIfNeeded()
            }
        }
    }

    private func cancelMonitoringLoop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private static func sanitizedPollingInterval(_ rawValue: Double?) -> TimeInterval {
        let candidate = rawValue ?? DefaultValues.monitorInterval
        guard candidate.isFinite, candidate >= 0.1 else {
            return DefaultValues.monitorInterval
        }

        return candidate
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((interval * 1_000_000_000).rounded())
    }

}
