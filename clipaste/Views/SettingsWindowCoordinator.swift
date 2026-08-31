import AppKit
import SwiftUI

enum SettingsWindowCoordinator {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("clipaste.settings.window")
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static var windowObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private static var activationPolicyTracker = SettingsActivationPolicyTracker()

    /// SwiftUI `Settings` 场景里 representable 拿到的 `window` 即设置窗口；弱引用避免仅靠 identifier 扫描不到的情况。
    private static weak var trackedSettingsWindow: NSWindow?

    /// 合并短时间内的多次刷新请求（如 `UserDefaults` 通知 + 其它路径），只保留最新一次延迟重试序列。
    private static var settingsTitleRefreshGeneration = 0

    @MainActor
    static func open(using openSettings: @escaping () -> Void) {
        promoteToRegularIfNeeded()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            openSettings()
            bringToFrontSoon()
        }
    }

    @MainActor
    static func openFromAppKit() {
        promoteToRegularIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
        bringToFrontSoon()
    }

    @MainActor
    static func register(window: NSWindow) {
        trackedSettingsWindow = window
        window.identifier = windowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
        noteSettingsPresentedIfNeeded()
        attachWindowObservers(to: window)
    }

    @MainActor
    private static func promoteToRegularIfNeeded() {
        let shouldPromote = activationPolicyTracker.noteSettingsRequested(
            usesAccessoryPolicy: shouldUseAccessoryPolicy,
            currentPolicy: currentActivationPolicy
        )
        guard shouldPromote else { return }

        NSApp.setActivationPolicy(.regular)
    }

    @MainActor
    private static func bringToFrontSoon() {
        let delays: [TimeInterval] = [0, 0.05, 0.2]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                bringToFrontIfPossible()
            }
        }
    }

    @MainActor
    private static func bringToFrontIfPossible() {
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.identifier == windowIdentifier }) else {
            return
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private static func noteSettingsPresentedIfNeeded() {
        activationPolicyTracker.noteSettingsPresented(
            usesAccessoryPolicy: shouldUseAccessoryPolicy,
            currentPolicy: currentActivationPolicy
        )
    }

    @MainActor
    private static func attachWindowObservers(to window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard windowObservers[windowID] == nil else { return }

        // SwiftUI 的 Settings 场景会在 App 生命周期内复用同一个 NSWindow 与内容视图树：
        // 第一次关闭后再打开时 viewDidMoveToWindow 不会再次触发，因此 register(window:) 也
        // 不会重新执行。这里保持监听器一直附着在窗口上，每次关闭都能恢复 accessory，从而
        // 避免第二次关闭后 Dock 图标残留。restoreAccessoryPolicyIfNeeded 自身是幂等的
        // （shouldRestoreAccessoryPolicy 用过即清），多次触发不会有副作用。
        windowObservers[windowID] = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                Task { @MainActor [weak window] in
                    restoreAccessoryPolicyIfNeeded(excluding: window)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    noteSettingsPresentedIfNeeded()
                }
            }
        ]
    }

    @MainActor
    private static func restoreAccessoryPolicyIfNeeded(excluding closingWindow: NSWindow? = nil) {
        // willCloseNotification 在窗口真正关闭前触发，此时 `closingWindow.isVisible`
        // 仍会返回 true。若不显式排除正在关闭的窗口，本方法会误以为设置窗还在显示，
        // 直接跳过恢复逻辑，导致 Dock 图标残留、必须强杀应用。
        let hasVisibleSettingsWindow = NSApp.windows.contains { window in
            window !== closingWindow
                && window.identifier == windowIdentifier
                && window.isVisible
        }

        let shouldRestore = activationPolicyTracker.noteSettingsClosed(
            usesAccessoryPolicy: shouldUseAccessoryPolicy,
            hasVisibleSettingsWindow: hasVisibleSettingsWindow
        )
        guard shouldRestore else { return }

        // 必须先让 App 失去激活状态，否则在 macOS Ventura/Sonoma 上
        // setActivationPolicy(.accessory) 可能被系统忽略，导致 Dock 图标残留。
        NSApp.deactivate()
        NSApp.setActivationPolicy(.accessory)
    }

    private static var shouldUseAccessoryPolicy: Bool {
        UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
    }

    private static var currentActivationPolicy: SettingsActivationPolicy {
        NSApp.activationPolicy() == .accessory ? .accessory : .regular
    }

    /// 与 `UserDefaults` 中 `appLanguage` 一致；`auto` 读取系统全局语言，显式语言用 `LocalizedStringResource(locale:)`，
    /// 减轻与进程内 `AppleLanguages` 缓存不一致的问题。
    @MainActor
    static func resolvedSettingsWindowTitle() -> String {
        let lang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
        let locale = lang.resolvedLocale
        let resource = LocalizedStringResource("Clipaste Settings", locale: locale, bundle: .main)
        return String(localized: resource)
    }

    /// 语言切换后系统 Settings 宿主有时会再次改写标题，故在数帧内多次应用。
    @MainActor
    static func refreshAllSettingsWindowTitles() {
        settingsTitleRefreshGeneration += 1
        let generation = settingsTitleRefreshGeneration
        let delays: [TimeInterval] = [0, 0.03, 0.08, 0.16, 0.32, 0.55, 1.0, 1.6]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    guard generation == settingsTitleRefreshGeneration else { return }
                    applySettingsWindowTitleToKnownWindows()
                }
            }
        }
    }

    @MainActor
    private static func applySettingsWindowTitleToKnownWindows() {
        let title = resolvedSettingsWindowTitle()
        var touched = Set<ObjectIdentifier>()

        func apply(_ window: NSWindow) {
            let oid = ObjectIdentifier(window)
            guard !touched.contains(oid) else { return }
            touched.insert(oid)
            window.title = title
        }

        if let window = trackedSettingsWindow, window.isVisible {
            apply(window)
        }
        for window in NSApp.windows where window.identifier == windowIdentifier {
            apply(window)
        }

        // 仍未命中时：SwiftUI Settings 窗口类名通常含 Settings，且不应误伤仅标题为「Clipaste」的引导窗。
        guard touched.isEmpty else { return }

        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            guard window.title != "Clipaste" else { continue }
            let typeName = String(describing: type(of: window))
            guard typeName.contains("Settings") else { continue }
            apply(window)
            break
        }
    }
}
