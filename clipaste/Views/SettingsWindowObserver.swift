import AppKit
import SwiftUI


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
        nonisolated(unsafe) private var toolbarObservation: NSKeyValueObservation?
        private weak var observedWindow: NSWindow?
        private weak var installedSidebarButton: NSButton?
        private var hasAppliedTrafficLightOffset = false

        deinit {
            pendingTitleWorkItem?.cancel()
            toolbarObservation?.invalidate()
            MainActor.assumeIsolated {
                stopObservingWindowClicks()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard let window else { return }
            observeWindowClicks(for: window)
            observeToolbarChanges(for: window)
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
                    ClipboardPanelManager.shared.hidePanelPreservingActiveApp()
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

        /// SwiftUI 的 Settings 场景会在场景刷新时异步重建 NSToolbar，仅靠固定延迟的清理
        /// 覆盖不到所有时机；这里用 KVO 保证 toolbar 一旦被重建就立刻再次移除。
        private func observeToolbarChanges(for window: NSWindow) {
            toolbarObservation?.invalidate()
            toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] _, change in
                guard (change.newValue ?? nil) != nil else { return }
                Task { @MainActor [weak self] in
                    self?.refreshToolbarChrome()
                }
            }
        }

        private func suppressSystemToolbarChrome() {
            guard let window else { return }
            if window.toolbar != nil {
                window.toolbar = nil
            }
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentBorderThickness(0, for: .maxY)
            hideTitlebarSeparatorViews()
        }

        /// `titlebarSeparatorStyle = .none` 偶尔不生效（系统仍保留 `NSTitlebarSeparatorView`），
        /// 直接在窗口框架视图里找到分隔线视图并隐藏。
        private func hideTitlebarSeparatorViews() {
            guard let frameView = window?.contentView?.superview else { return }
            hideTitlebarSeparators(in: frameView)
        }

        private func hideTitlebarSeparators(in view: NSView) {
            for subview in view.subviews {
                if String(describing: type(of: subview)).contains("TitlebarSeparator") {
                    subview.isHidden = true
                } else {
                    hideTitlebarSeparators(in: subview)
                }
            }
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
