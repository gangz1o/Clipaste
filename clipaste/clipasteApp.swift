import SwiftUI
import AppKit
import KeyboardShortcuts
import SwiftData

extension Notification.Name {
    static let openSettingsIntent = Notification.Name("openSettingsIntent")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingDefaultsKey = "hasCompletedOnboarding"
    private let globalShortcutNames: [KeyboardShortcuts.Name] = [
        .toggleClipboardPanel,
        .toggleVerticalClipboard,
        .nextList,
        .prevList,
        .clearHistory,
        .toggleFavoriteSelection
    ]
    nonisolated(unsafe) private var onboardingStateObserver: NSObjectProtocol?
    private var lastKnownOnboardingState = false
    private var lastObservedAppLanguageRaw: String?
    private var onboardingWindow: NSWindow?
    private var hasRegisteredGlobalShortcuts = false

    private func normalizedAppLanguageStorageRaw() -> String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return raw.isEmpty ? AppLanguage.auto.rawValue : raw
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        lastKnownOnboardingState = hasCompleted
        updateActivationPolicy(hasCompletedOnboarding: hasCompleted)

        if !hasCompleted {
            presentOnboardingWindow()
        }

        registerGlobalShortcutsIfNeeded()

        // Verify accessibility permission so KeyboardShortcuts can use the privileged
        // CGEventTap (session-level) instead of the degraded NSEvent global monitor.
        // Without this, apps like Xcode that handle ⌘⇧C internally will swallow the
        // event before our monitor sees it.
        checkAndRequestAccessibility()

        // 提前构建隐藏面板与其 SwiftUI 视图树，让首屏展示前就完成
        // ViewModel 初始化、warm cache 订阅与基础窗口准备，减少第一次呼出时的白屏等待。
        ClipboardPanelManager.shared.preparePanelIfNeeded()

        lastObservedAppLanguageRaw = normalizedAppLanguageStorageRaw()

        onboardingStateObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let langRaw = self.normalizedAppLanguageStorageRaw()
                if langRaw != self.lastObservedAppLanguageRaw {
                    self.lastObservedAppLanguageRaw = langRaw
                    SettingsWindowCoordinator.refreshAllSettingsWindowTitles()
                }

                let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: self.onboardingDefaultsKey)
                guard hasCompletedOnboarding != self.lastKnownOnboardingState else { return }

                self.lastKnownOnboardingState = hasCompletedOnboarding
                self.updateActivationPolicy(hasCompletedOnboarding: hasCompletedOnboarding)

                if hasCompletedOnboarding {
                    self.dismissOnboardingWindow()
                } else {
                    self.presentOnboardingWindow()
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            AppPreferencesStore.shared.refreshLaunchAtLoginStatus()
        }
    }

    private func handleTogglePanelShortcut() {
        ClipboardPanelManager.shared.togglePanel()
    }

    private func handleToggleVerticalClipboardShortcut() {
        let defaults = UserDefaults.standard
        let currentLayoutMode = AppLayoutMode(
            rawValue: defaults.string(forKey: "clipboardLayout") ?? AppLayoutMode.horizontal.rawValue
        ) ?? .horizontal
        let layoutMode: AppLayoutMode = currentLayoutMode == .vertical ? .horizontal : .vertical
        let isVerticalLayout = layoutMode == .vertical

        defaults.set(layoutMode.rawValue, forKey: "clipboardLayout")
        defaults.set(isVerticalLayout, forKey: "isVerticalLayout")
    }

    private func registerGlobalShortcutsIfNeeded() {
        guard !hasRegisteredGlobalShortcuts else { return }
        hasRegisteredGlobalShortcuts = true

        KeyboardShortcuts.onKeyDown(for: .toggleClipboardPanel) { [weak self] in
            self?.handleTogglePanelShortcut()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleVerticalClipboard) { [weak self] in
            self?.handleToggleVerticalClipboardShortcut()
        }

        KeyboardShortcuts.onKeyDown(for: .nextList) {
            NotificationCenter.default.post(name: .selectNextGroup, object: nil)
        }

        KeyboardShortcuts.onKeyDown(for: .prevList) {
            NotificationCenter.default.post(name: .selectPreviousGroup, object: nil)
        }

        KeyboardShortcuts.onKeyDown(for: .clearHistory) {
            StorageManager.shared.clearUnpinnedHistory()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleFavoriteSelection) {
            NotificationCenter.default.post(name: .toggleFavoriteSelectionIntent, object: nil)
        }
    }

    private func refreshGlobalShortcuts() {
        KeyboardShortcuts.disable(globalShortcutNames)
        KeyboardShortcuts.enable(globalShortcutNames)
    }

    /// Ensures the privileged CGEventTap (session-level) is available.
    /// Without Accessibility permission, KeyboardShortcuts falls back to
    /// NSEvent.addGlobalMonitorForEvents which is blocked by apps like Xcode
    /// that handle the key event internally before it propagates.
    private func checkAndRequestAccessibility() {
        // Attempt to obtain the trusted status.  Passing `prompt: true` makes
        // macOS immediately show the "clipaste wants to control this computer"
        // system dialog so the user can grant access in one click.
        let options: NSDictionary = [
            "AXTrustedCheckOptionPrompt": true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            // Permission already granted – KeyboardShortcuts will use the
            // privileged tap automatically; nothing more to do.
            return
        }

        // Permission was just requested.  Refresh the already-registered
        // shortcuts after a short delay so KeyboardShortcuts can retry with
        // the privileged tap without appending duplicate handlers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task { @MainActor in
                self.refreshGlobalShortcuts()
            }
        }
    }

    deinit {
        if let onboardingStateObserver {
            NotificationCenter.default.removeObserver(onboardingStateObserver)
        }
    }

    private func updateActivationPolicy(hasCompletedOnboarding: Bool) {
        if hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func presentOnboardingWindow() {
        let window = onboardingWindow ?? makeOnboardingWindow()
        onboardingWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOnboardingWindow() {
        onboardingWindow?.orderOut(nil)
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func makeOnboardingWindow() -> NSWindow {
        let appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
        let rootView = OnboardingView()
            .environment(\.locale, appLanguage.locale ?? .current)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "Clipaste"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 520, height: 460))
        window.center()

        window.delegate = self
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil
    }
}

@main
struct clipasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var preferencesStore = AppPreferencesStore.shared
    @StateObject private var settingsViewModel = SettingsViewModel.shared
    @StateObject private var runtimeStore = ClipboardRuntimeStore.shared
    private let appUpdateViewModel = AppUpdateViewModel.shared
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    init() {
        Task { @MainActor in
            AppUpdateViewModel.shared.start()
        }
    }

    var body: some Scene {
        // Register standard macOS Settings Window
        Settings {
            SettingsView()
                .environmentObject(preferencesStore)
                .environmentObject(settingsViewModel)
                .environmentObject(runtimeStore)
                .modelContainer(runtimeStore.container)
                .id(appLanguage.rawValue)
                .environment(\.locale, appLanguage.locale ?? .current)
                .environment(appUpdateViewModel)
                .preferredColorScheme(appTheme.colorScheme)
        }
        .defaultSize(width: 620, height: 580)
        .windowResizability(.contentMinSize)

        // Status Bar Menu to access app functions
        MenuBarExtra("Clipaste", image: "MenuBarIcon") {
            MenuBarExtraContent()
                .environmentObject(preferencesStore)
                .environmentObject(runtimeStore)
                .modelContainer(runtimeStore.container)
                .id("\(runtimeStore.rootIdentity)-\(appLanguage.rawValue)")
                .environment(\.locale, appLanguage.locale ?? .current)
                .environment(appUpdateViewModel)
        }
    }
}

private struct MenuBarExtraContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Button("Settings…") {
                SettingsWindowCoordinator.open {
                    openSettings()
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Clipaste") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
