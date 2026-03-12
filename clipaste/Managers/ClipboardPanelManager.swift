import AppKit
import SwiftUI

/// ClipboardPanelManager is responsible for managing the floating clipboard history panel.
/// It uses a borderless panel that follows the mouse's screen and presents in front of the Dock.
class ClipboardPanelManager {
    static let shared = ClipboardPanelManager()
    private static let panelLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    private var panel: ClipboardPanel?
    private var eventMonitor: Any?
    private var layoutObserver: Any?
    private var pinObserver: Any?
    private var forceHideObserver: Any?

    /// 记录呼出面板前正在活跃的 App（如微信、Safari），用于关闭面板时精准归还焦点
    private var previousActiveApp: NSRunningApplication?

    /// Whether the panel is pinned (won't auto-dismiss on outside click).
    private var isPinned: Bool = UserDefaults.standard.bool(forKey: "isPanelPinned")

    /// Indicates whether the panel is currently visible to the user.
    private(set) var isVisible: Bool = false

    private init() {
        setupPanel()
        setupLayoutObserver()
        setupPinObserver()
        setupForceHideObserver()
    }

    private func setupPanel() {
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable]

        let panel = ClipboardPanel(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 0.0
        panel.minSize = NSSize(width: 320, height: 450)

        panel.level = Self.panelLevel
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let hostingController = NSHostingController(rootView: ClipboardMainView())
        panel.contentViewController = hostingController

        self.panel = panel
    }

    // MARK: - Observers

    private func setupLayoutObserver() {
        layoutObserver = NotificationCenter.default.addObserver(
            forName: .clipboardLayoutModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let layout = notification.object as? AppLayoutMode else { return }
            self.updatePanelSize(layout: layout, animated: true)
        }
    }

    private func setupPinObserver() {
        pinObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TogglePinStatus"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let pinned = notification.object as? Bool {
                self.isPinned = pinned
                // 固定时提升窗口层级，防止被其他 App 遮挡
                self.panel?.level = pinned ? .floating : Self.panelLevel
            }
        }
    }

    private func setupForceHideObserver() {
        forceHideObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HidePanelForce"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceHidePanel()
        }
    }

    // MARK: - Panel Size

    /// Returns the target frame for vertical mode, applying the user-selected follow mode
    /// and strict screen-edge collision detection.
    private func verticalFrame(on screen: NSScreen) -> NSRect {
        let sf = screen.visibleFrame
        let width: CGFloat = 360
        let height: CGFloat = 650
        let modeRaw = UserDefaults.standard.string(forKey: "verticalFollowMode") ?? VerticalFollowMode.mouse.rawValue
        let mode = VerticalFollowMode(rawValue: modeRaw) ?? .mouse

        switch mode {
        case .statusBar:
            // Top-right safe area, just below the menu bar
            let x = sf.maxX - width - 12
            let y = sf.maxY - height - 12
            return NSRect(x: x, y: y, width: width, height: height)

        case .mouse:
            let mouseLoc = NSEvent.mouseLocation
            var x = mouseLoc.x - width / 2
            var y = mouseLoc.y - height / 2
            // Edge collision clamping
            if x < sf.minX { x = sf.minX + 12 }
            if x + width > sf.maxX { x = sf.maxX - width - 12 }
            if y < sf.minY { y = sf.minY + 12 }
            if y + height > sf.maxY { y = sf.maxY - height - 12 }
            return NSRect(x: x, y: y, width: width, height: height)

        case .lastPosition:
            let current = panel?.frame ?? .zero
            // Cold-start fallback: center on screen
            if current.minX == 0 && current.minY == 0 {
                let x = sf.minX + (sf.width - width) / 2
                let y = sf.minY + (sf.height - height) / 2
                return NSRect(x: x, y: y, width: width, height: height)
            }
            // Preserve last origin but enforce correct size
            return NSRect(x: current.minX, y: current.minY, width: width, height: height)
        }
    }

    /// Returns the target frame for the given layout, using the correct positioning strategy.
    private func panelFrame(for layout: AppLayoutMode, on screen: NSScreen) -> NSRect {
        let sf = screen.visibleFrame
        switch layout {
        case .horizontal:
            let height: CGFloat = 320
            return NSRect(x: sf.minX, y: sf.minY, width: sf.width, height: height)
        case .vertical:
            return verticalFrame(on: screen)
        }
    }

    private func updatePanelSize(layout: AppLayoutMode, animated: Bool) {
        guard let panel, let screen = screenContainingMouse() ?? NSScreen.main else { return }
        let target = panelFrame(for: layout, on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: false)
        }

        // 仅允许从 Header 区域拖动（通过 WindowDragArea 视图实现），禁止全窗口背景拖移
        panel.isMovableByWindowBackground = false
        panel.isMovable = true
    }

    // MARK: - Show / Hide

    /// Toggles the visibility of the clipboard panel.
    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Shows the panel sized for the current layout mode, then animates it in.
    func showPanel() {
        guard !isVisible, let panel else { return }

        // 0. 拍照留底：在呼出面板之前，记下当前正活跃的 App
        //    必须在 activate / makeKeyAndOrderFront 之前调用，否则 frontmostApplication 会变成自己
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // 每次呼出先读一次 Toggle 的底层 Bool（isVerticalLayout 是设置页的权威来源），
        // 再同步到 AppLayoutMode 供 panelFrame 使用，保证冷启动尺寸正确。
        let isVertical = UserDefaults.standard.bool(forKey: "isVerticalLayout")
        let layout: AppLayoutMode = isVertical ? .vertical : .horizontal
        let screen = screenContainingMouse() ?? NSScreen.main

        // 仅允许从 Header 区域拖动（通过 WindowDragArea 视图实现），禁止全窗口背景拖移
        panel.isMovableByWindowBackground = false
        panel.isMovable = true

        let visibleFrame = panelFrame(for: layout, on: screen ?? NSScreen.main!)

        // Start slightly below the screen edge for horizontal; fade-in only for vertical.
        let hiddenFrame: NSRect
        if layout == .horizontal {
            hiddenFrame = NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY - 20,
                width: visibleFrame.width,
                height: visibleFrame.height
            )
        } else {
            // For vertical panel just fade in without sliding
            hiddenFrame = visibleFrame
        }

        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 0.0

        // ⚠️ 不再调用 NSApp.activate(ignoringOtherApps:) — 那会把菜单栏切成自己的 App，
        //    导致目标 App 失去焦点，Cmd+V 无法命中正确窗口。
        //    .nonactivatingPanel 已经允许面板接收按键，无需抢占 App 级焦点。
        panel.makeKeyAndOrderFront(nil)
        panel.becomeFirstResponder()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(visibleFrame, display: true)
            panel.animator().alphaValue = 1.0
        }) { [weak self] in
            self?.isVisible = true
            self?.setupEventMonitor()
        }

    }

    /// Hides the clipboard panel — intercepted when the panel is pinned.
    func hidePanel() {
        guard isVisible else { return }
        if isPinned { return } // 图钉固定时，拦截隐藏指令
        executeHide()
    }

    /// Force-hides the panel regardless of pin state (used by paste/settings/about).
    func forceHidePanel() {
        guard isVisible else { return }
        executeHide()
    }

    private func executeHide() {
        guard let panel = panel else { return }
        removeEventMonitor()
        panel.orderOut(nil)
        panel.resignKey()
        isVisible = false

        // 将焦点精准归还给呼出面板前的 App（保证 Cmd+V 粘贴命中目标窗口）
        if let app = previousActiveApp, !app.isTerminated {
            app.activate()
        }
        previousActiveApp = nil
    }

    private func dismissPanelOnly() {
        executeHide()
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func hasOtherActiveWindows() -> Bool {
        guard let panel else { return false }
        return NSApplication.shared.windows.filter(\.isVisible).contains { $0 !== panel }
    }

    // MARK: - Event Monitoring

    private func setupEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // 始终走 hidePanel()，内部会检查图钉状态
            self.hidePanel()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let clipboardLayoutModeChanged = Notification.Name("clipboardLayoutModeChanged")
}
