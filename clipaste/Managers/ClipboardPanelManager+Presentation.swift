import AppKit
import SwiftUI
import SwiftData

@MainActor
extension ClipboardPanelManager {
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

        let layout = AppLayoutMode(
            rawValue: UserDefaults.standard.string(forKey: "clipboardLayout") ?? AppLayoutMode.horizontal.rawValue
        ) ?? .horizontal
        guard let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first else {
            previousActiveApp = nil
            return
        }

        applyPanelMovability(for: layout, panel: panel)
        panel.hasShadow = (layout == .vertical || layout == .compact)


        let visibleFrame = panelFrame(for: layout, on: screen)

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
            Task { @MainActor [weak self] in
                self?.isVisible = true
                self?.setupEventMonitor()
            }
        }

    }

    func applyPanelMovability(for layout: AppLayoutMode, panel: ClipboardPanel) {
        panel.isMovableByWindowBackground = false
        panel.isMovable = layout == .vertical || layout == .compact
    }

    /// Hides the clipboard panel — intercepted when the panel is pinned or showing a modal dialog.
    func hidePanel() {
        guard isVisible else { return }
        if isPinned { return } // 图钉固定时，拦截隐藏指令
        if suppressHide { return } // 模态对话框（如删除确认 alert）激活时，拦截隐藏指令
        executeHide()
    }

    /// Hides only the clipboard panel, keeping the currently active Clipaste window interactive.
    func hidePanelPreservingActiveApp() {
        guard isVisible else { return }
        if isPinned { return }
        if suppressHide { return }
        executeHide(restorePreviousActiveApp: false)
    }

    /// Force-hides the panel regardless of pin state (used by paste/settings/about).
    func forceHidePanel() {
        guard isVisible else { return }
        executeHide()
    }

    func executeHide(restorePreviousActiveApp: Bool = true) {
        guard let panel = panel else { return }
        removeEventMonitor()
        panel.orderOut(nil)
        panel.resignKey()
        isVisible = false

        // 将焦点精准归还给呼出面板前的 App（保证 Cmd+V 粘贴命中目标窗口）
        if restorePreviousActiveApp, let app = previousActiveApp, !app.isTerminated {
            app.activate()
        }
        previousActiveApp = nil
    }

    func dismissPanelOnly() {
        executeHide()
    }


    func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    func hasOtherActiveWindows() -> Bool {
        guard let panel else { return false }
        return NSApplication.shared.windows.filter(\.isVisible).contains { $0 !== panel }
    }

    // MARK: - Event Monitoring

    func setupEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                // 始终走 hidePanel()，内部会检查图钉状态
                self.hidePanel()
            }
        }
    }

    func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
