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

    /// Indicates whether the panel is currently visible to the user.
    private(set) var isVisible: Bool = false

    private init() {
        setupPanel()
        setupLayoutObserver()
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

    // MARK: - Layout Observer

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
            let height: CGFloat = 340
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

        // 每次呼出先读一次 Toggle 的底层 Bool（isVerticalLayout 是设置页的权威来源），
        // 再同步到 AppLayoutMode 供 panelFrame 使用，保证冷启动尺寸正确。
        let isVertical = UserDefaults.standard.bool(forKey: "isVerticalLayout")
        let layout: AppLayoutMode = isVertical ? .vertical : .horizontal
        let screen = screenContainingMouse() ?? NSScreen.main

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

        NSApp.activate(ignoringOtherApps: true)
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

    /// Hides the clipboard panel without affecting other app windows.
    func hidePanel() {
        guard isVisible else { return }
        dismissPanelOnly()
    }

    private func dismissPanelOnly() {
        guard let panel = panel else { return }
        removeEventMonitor()
        panel.orderOut(nil)
        panel.resignKey()
        isVisible = false
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
            if self.hasOtherActiveWindows() {
                self.dismissPanelOnly()
            } else {
                self.hidePanel()
            }
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
