import AppKit
import SwiftUI

enum SettingsWindowCoordinator {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("clipaste.settings.window")
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private static var shouldRestoreAccessoryPolicy = false

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
        attachCloseObserver(to: window)
    }

    @MainActor
    private static func promoteToRegularIfNeeded() {
        guard shouldUseAccessoryPolicy else { return }
        guard NSApp.activationPolicy() == .accessory else { return }

        shouldRestoreAccessoryPolicy = true
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

        attachCloseObserver(to: window)

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private static func attachCloseObserver(to window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard closeObservers[windowID] == nil else { return }

        closeObservers[windowID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                removeCloseObserver(for: window)
                scheduleAccessoryPolicyRestoreAfterClose()
            }
        }
    }

    @MainActor
    private static func removeCloseObserver(for window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard let observer = closeObservers.removeValue(forKey: windowID) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    @MainActor
    private static func scheduleAccessoryPolicyRestoreAfterClose() {
        let delays: [TimeInterval] = [0, 0.05, 0.2]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    guard shouldRestoreAccessoryPolicy else { return }
                    restoreAccessoryPolicyIfNeeded()
                }
            }
        }
    }

    @MainActor
    private static func restoreAccessoryPolicyIfNeeded() {
        guard shouldRestoreAccessoryPolicy else { return }
        guard shouldUseAccessoryPolicy else {
            shouldRestoreAccessoryPolicy = false
            return
        }

        let hasVisibleSettingsWindow = NSApp.windows.contains {
            $0.identifier == windowIdentifier && $0.isVisible
        }

        guard !hasVisibleSettingsWindow else { return }

        // 必须先让 App 失去激活状态，否则在 macOS Ventura/Sonoma 上
        // setActivationPolicy(.accessory) 可能被系统忽略，导致 Dock 图标残留。
        NSApp.deactivate()
        NSApp.setActivationPolicy(.accessory)
        shouldRestoreAccessoryPolicy = false
    }

    private static var shouldUseAccessoryPolicy: Bool {
        UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
    }

    /// 与 `UserDefaults` 中 `appLanguage` 一致；`auto` 读取系统全局语言，显式语言用 `LocalizedStringResource(locale:)`，
    /// 减轻与进程内 `AppleLanguages` 缓存不一致的问题。
    @MainActor
    fileprivate static func resolvedSettingsWindowTitle() -> String {
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

struct SettingsWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        // 布局阶段 window 常为 nil，仅在此处 return 会导致标题永远不随语言更新。
        trackingView.scheduleApplyWindowTitle()
        trackingView.scheduleToolbarChromeLayout()
    }

    private final class TrackingView: NSView {
        private let sidebarButtonTag = 9_421
        nonisolated(unsafe) private var pendingTitleWorkItem: DispatchWorkItem?
        nonisolated(unsafe) private var localMouseMonitor: Any?
        private weak var observedWindow: NSWindow?
        private weak var installedSidebarButton: NSButton?
        private var hasAppliedTrafficLightOffset = false

        deinit {
            pendingTitleWorkItem?.cancel()
            stopObservingWindowClicks()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard let window else { return }
            observeWindowClicks(for: window)
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.resizable)
            window.toolbar = nil
            window.setContentBorderThickness(0, for: .maxY)
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
            window.standardWindowButton(.zoomButton)?.isEnabled = true

            SettingsWindowCoordinator.register(window: window)

            applyWindowTitleIfNeeded()
            scheduleToolbarChromeLayout()
        }

        func scheduleApplyWindowTitle() {
            applyWindowTitleIfNeeded()
            pendingTitleWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.applyWindowTitleIfNeeded()
            }
            pendingTitleWorkItem = item
            DispatchQueue.main.async(execute: item)
        }

        func scheduleToolbarChromeLayout() {
            let delays: [TimeInterval] = [0, 0.05, 0.2, 0.5, 1.0]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.refreshToolbarChrome()
                }
            }
        }

        private func applyWindowTitleIfNeeded() {
            guard let window else { return }
            window.title = SettingsWindowCoordinator.resolvedSettingsWindowTitle()
        }

        private func observeWindowClicks(for window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObservingWindowClicks()
            observedWindow = window

            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let observedWindow = self.observedWindow else {
                    return event
                }

                if event.window === observedWindow {
                    ClipboardPanelManager.shared.hidePanel()
                }

                return event
            }
        }

        private func stopObservingWindowClicks() {
            if let localMouseMonitor {
                NSEvent.removeMonitor(localMouseMonitor)
                self.localMouseMonitor = nil
            }
            observedWindow = nil
        }

        private func refreshToolbarChrome() {
            suppressSystemToolbarChrome()
            removeSystemSidebarToolbarItems()
            applyTrafficLightLayout()
        }

        private func suppressSystemToolbarChrome() {
            guard let window else { return }
            window.toolbar = nil
            window.titlebarSeparatorStyle = .none
            window.setContentBorderThickness(0, for: .maxY)
        }

        private func removeSystemSidebarToolbarItems() {
            guard let toolbar = window?.toolbar else { return }

            let unwantedIdentifiers: Set<NSToolbarItem.Identifier> = [
                .toggleSidebar,
                .sidebarTrackingSeparator
            ]

            let indexes = toolbar.items.enumerated()
                .compactMap { index, item in
                    unwantedIdentifiers.contains(item.itemIdentifier) ? index : nil
                }

            for index in indexes.reversed() {
                toolbar.removeItem(at: index)
            }
        }

        private func applyTrafficLightLayout() {
            guard let window else { return }
            guard let closeButton = window.standardWindowButton(.closeButton),
                  let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
                  let zoomButton = window.standardWindowButton(.zoomButton) else {
                return
            }

            if !hasAppliedTrafficLightOffset {
                let xOffset: CGFloat = 4
                let yOffset: CGFloat = -1
                let buttons = [closeButton, miniaturizeButton, zoomButton]
                for button in buttons {
                    var origin = button.frame.origin
                    origin.x += xOffset
                    origin.y += yOffset
                    button.setFrameOrigin(origin)
                }
                hasAppliedTrafficLightOffset = true
            }

            installCustomSidebarButton(nextTo: zoomButton)
        }

        private func installCustomSidebarButton(nextTo zoomButton: NSButton) {
            guard let titlebarView = zoomButton.superview else { return }
            let size = NSSize(width: 30, height: 24)
            let origin = NSPoint(
                x: zoomButton.frame.maxX + 12,
                y: zoomButton.frame.midY - (size.height / 2)
            )

            if let existing = installedSidebarButton {
                existing.frame = NSRect(origin: origin, size: size)
                return
            }

            if let stale = titlebarView.viewWithTag(sidebarButtonTag) as? NSButton {
                stale.removeFromSuperview()
            }

            let image = NSImage(
                systemSymbolName: "sidebar.left",
                accessibilityDescription: String(localized: "Toggle Sidebar")
            )
            let newButton = NSButton(image: image ?? NSImage(), target: self, action: #selector(toggleSidebar))
            newButton.tag = sidebarButtonTag
            newButton.isBordered = false
            newButton.imagePosition = .imageOnly
            newButton.contentTintColor = .secondaryLabelColor
            newButton.setButtonType(.momentaryPushIn)
            newButton.focusRingType = .none
            newButton.setAccessibilityLabel(String(localized: "Toggle Sidebar"))
            newButton.frame = NSRect(origin: origin, size: size)
            titlebarView.addSubview(newButton)
            installedSidebarButton = newButton
        }

        @objc
        private func toggleSidebar() {
            NotificationCenter.default.post(name: .toggleSettingsSidebarIntent, object: nil)
        }
    }
}

struct WindowAppearanceObserver: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        TrackingView(theme: theme)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        trackingView.update(theme: theme)
    }

    private final class TrackingView: NSView {
        private var theme: AppTheme

        init(theme: AppTheme) {
            self.theme = theme
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTheme()
        }

        func update(theme: AppTheme) {
            self.theme = theme
            applyTheme()
        }

        private func applyTheme() {
            let targetAppearanceName = theme.nsAppearanceName
            let targetAppearance = theme.nsAppearance

            if shouldApplyAppearance(targetAppearanceName, to: window?.appearance) {
                window?.appearance = targetAppearance
            }

            // When reverting to "follow system" (targetAppearance == nil), also reset
            // the app-level appearance so macOS regenerates the effective appearance
            // from the system setting. Guarding this assignment keeps theme changes
            // idempotent, which avoids repeated appearance invalidation loops.
            if shouldApplyAppearance(targetAppearanceName, to: NSApp.appearance) {
                NSApp.appearance = targetAppearance
            }
        }

        private func shouldApplyAppearance(_ targetName: NSAppearance.Name?, to currentAppearance: NSAppearance?) -> Bool {
            if targetName == nil {
                return currentAppearance != nil
            }

            return currentAppearance?.name != targetName
        }
    }
}

struct SettingsScrollChromeObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.scheduleApply()
    }

    final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleApply()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleApply()
        }

        func scheduleApply() {
            let delays: [TimeInterval] = [0, 0.05, 0.2]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.applyScrollChromeHidden()
                }
            }
        }

        private func applyScrollChromeHidden() {
            guard let rootView = window?.contentView else { return }

            for scrollView in allScrollViews(in: rootView) {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.isHidden = true
                scrollView.horizontalScroller?.isHidden = true
            }
        }

        private func allScrollViews(in rootView: NSView) -> [NSScrollView] {
            var queue: [NSView] = [rootView]
            var scrollViews: [NSScrollView] = []

            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? NSScrollView {
                    scrollViews.append(scrollView)
                }

                queue.append(contentsOf: view.subviews)
            }

            return scrollViews
        }
    }
}

extension View {
    func settingsScrollChromeHidden() -> some View {
        self
            .scrollIndicators(.hidden)
            .background(SettingsScrollChromeObserver())
    }
}
