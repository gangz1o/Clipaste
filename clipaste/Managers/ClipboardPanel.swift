import AppKit

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Cache the NSScrollView reference to avoid repeated hierarchy traversal.
    private weak var cachedScrollView: NSScrollView?

    /// 强制注入 `.nonactivatingPanel`：面板可以接收键盘输入（搜索框正常打字），
    /// 但不会切走目标 App（如微信、Safari）的焦点，确保 Cmd+V 能准确粘贴到原来的 App。
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style.union(.nonactivatingPanel),
            backing: backingStoreType,
            defer: flag
        )
    }

    // MARK: - Vertical→Horizontal scroll redirection

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel,
           handleVerticalToHorizontalScroll(event) {
            // Event consumed — do NOT call super
            return
        }
        super.sendEvent(event)
    }

    /// Returns `true` if the event was consumed (scrolled horizontally).
    private func handleVerticalToHorizontalScroll(_ event: NSEvent) -> Bool {
        // Only redirect when the layout is horizontal
        let isVertical = UserDefaults.standard.bool(forKey: "isVerticalLayout")
        guard !isVertical else { return false }

        // Don't touch events that already have Shift (user intentionally scrolling horizontally)
        guard !event.modifierFlags.contains(.shift) else { return false }

        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        // Only act when vertical component dominates
        guard abs(dy) > abs(dx), dy != 0 else { return false }

        // Find the horizontal NSScrollView (cached for performance)
        guard let scrollView = findHorizontalScrollView() else { return false }

        // ── Manually scroll the NSScrollView horizontally ──
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let delta = dy * multiplier

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x -= delta

        // Clamp to valid scroll range
        let documentWidth = scrollView.documentView?.frame.width ?? 0
        let visibleWidth  = clipView.bounds.width
        let maxX = max(0, documentWidth - visibleWidth)
        origin.x = max(0, min(origin.x, maxX))

        clipView.scroll(to: NSPoint(x: origin.x, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    /// BFS through the content view hierarchy to find the main content NSScrollView.
    /// Skips small scroll views (e.g., header group pill bar) to avoid intercepting
    /// scroll events meant for the main horizontal list.
    private func findHorizontalScrollView() -> NSScrollView? {
        if let sv = cachedScrollView, sv.window === self,
           sv.frame.width > 200 { return sv }

        cachedScrollView = nil
        guard let root = contentView else { return nil }
        var queue: [NSView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let sv = view as? NSScrollView,
               sv.frame.width > 200 {
                // Only cache the main content scroll view (wide enough to be the list)
                cachedScrollView = sv
                return sv
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}
