import SwiftUI
import AppKit
import CoreServices
import KeyboardShortcuts
import SwiftData

extension Notification.Name {
    static let openSettingsIntent = Notification.Name("openSettingsIntent")
    static let toggleSettingsSidebarIntent = Notification.Name("toggleSettingsSidebarIntent")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingDefaultsKey = "hasCompletedOnboarding"
    private let hideMenuBarIconDefaultsKey = "hideMenuBarIcon"
    private let globalShortcutNames: [KeyboardShortcuts.Name] = [
        .toggleClipboardPanel
    ]
    nonisolated(unsafe) private var onboardingStateObserver: NSObjectProtocol?
    private var lastKnownOnboardingState = false
    private var lastObservedAppLanguageRaw: String?
    private var onboardingWindow: NSWindow?
    private var hasRegisteredGlobalShortcuts = false
    private var statusBarController: StatusBarController?
    private var wasLaunchedAtLoginItem = false
    private var hasCompletedDeferredStartupWork = false

    private func normalizedAppLanguageStorageRaw() -> String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return raw.isEmpty ? AppLanguage.auto.rawValue : raw
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        wasLaunchedAtLoginItem = resolveLaunchedAtLoginItemFlag()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreviewPanelMode.registerDefault()
        PreviewPanelMode.migrateStoredPreference()

        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }

        syncStatusBarControllerVisibility()

        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        lastKnownOnboardingState = hasCompleted
        updateActivationPolicy(hasCompletedOnboarding: hasCompleted)

        if !hasCompleted, !wasLaunchedAtLoginItem {
            presentOnboardingWindow()
        }

        registerGlobalShortcutsIfNeeded()
        performDeferredStartupWorkIfNeeded()

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

                self.syncStatusBarControllerVisibility()

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
            performDeferredStartupWorkIfNeeded()

            if !lastKnownOnboardingState, onboardingWindow == nil {
                presentOnboardingWindow()
            }

            AppPreferencesStore.shared.refreshLaunchAtLoginStatus()
            ClipboardRuntimeStore.shared.handleAppBecameActive()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        handleForegroundReopenRequest()
        return false
    }

    private func handleTogglePanelShortcut() {
        ClipboardPanelManager.shared.togglePanel()
    }

    private func handleForegroundReopenRequest() {
        if !lastKnownOnboardingState {
            presentOnboardingWindow()
            return
        }

        SettingsWindowCoordinator.openFromAppKit()
    }

    private func registerGlobalShortcutsIfNeeded() {
        guard !hasRegisteredGlobalShortcuts else { return }
        hasRegisteredGlobalShortcuts = true

        // The clipboard panel toggle is the only true global shortcut — it is the entry point
        // that summons the panel from any frontmost app.
        KeyboardShortcuts.onKeyDown(for: .toggleClipboardPanel) { [weak self] in
            self?.handleTogglePanelShortcut()
        }

        // NOTE: All other panel-related shortcuts (toggle layout, next/previous list, toggle
        // favorite, clear history, Cmd+Backspace delete) are intentionally NOT registered here.
        // KeyboardShortcuts uses a system-wide CGEventTap, so any registered binding is consumed
        // even when the panel is hidden — that breaks the same key combo inside other apps
        // (e.g. ⌘→ in Excel for "Next List"). Those actions are dispatched inside
        // handlePanelKeyDown() via the local NSEvent monitor that only fires while the panel is
        // visible, so user-configured bindings still work in-app without leaking globally.
    }

    private func refreshGlobalShortcuts() {
        KeyboardShortcuts.disable(globalShortcutNames)
        KeyboardShortcuts.enable(globalShortcutNames)
    }

    private func resolveLaunchedAtLoginItemFlag() -> Bool {
        let keyword = AEKeyword(keyAELaunchedAsLogInItem)
        return NSAppleEventManager.shared()
            .currentAppleEvent?
            .paramDescriptor(forKeyword: keyword)?
            .booleanValue ?? false
    }

    private func performDeferredStartupWorkIfNeeded() {
        guard !hasCompletedDeferredStartupWork else { return }
        guard !wasLaunchedAtLoginItem || NSApp.isActive else { return }

        hasCompletedDeferredStartupWork = true

        // 登录项冷启动时先保持最小可用启动路径，等真正进入前台后再做权限提示；
        // 避免在系统刚恢复登录会话时立刻弹 TCC 对话框卡住主界面。
        checkAndRequestAccessibility()

        // 面板预热只影响首屏性能，不影响功能，延后一拍让 AppKit/SwiftUI 先完成基础启动。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            ClipboardPanelManager.shared.preparePanelIfNeeded()
        }

        // Sparkle 在 menubar/accessory 场景下不适合跟冷启动抢主线程和窗口时序；
        // 延后启动即可保留更新能力，同时避开登录项自动启动路径。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AppUpdateViewModel.shared.start()
        }
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

    private func syncStatusBarControllerVisibility() {
        let shouldHideMenuBarIcon = UserDefaults.standard.bool(forKey: hideMenuBarIconDefaultsKey)
        if shouldHideMenuBarIcon {
            statusBarController = nil
        } else if statusBarController == nil {
            statusBarController = StatusBarController()
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
            .environment(\.locale, appLanguage.resolvedLocale)
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
    private let runtimeStore = ClipboardRuntimeStore.shared
    private let appUpdateViewModel = AppUpdateViewModel.shared
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    init() {
        #if DEBUG
        // 命中 --initialize-cloudkit-schema 时同步执行并退出,不进入正常启动流程。
        CloudKitSchemaInitializer.runIfRequested()
        #endif
    }

    var body: some Scene {
        // Register standard macOS Settings Window
        Settings {
            SettingsView()
                .environmentObject(preferencesStore)
                .environmentObject(settingsViewModel)
                .environment(runtimeStore)
                .modelContainer(runtimeStore.container)
                .environment(\.locale, appLanguage.resolvedLocale)
                .environment(appUpdateViewModel)
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
    }
}
