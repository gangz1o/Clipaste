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
        let layout = AppLayoutMode(
            rawValue: UserDefaults.standard.string(forKey: "clipboardLayout") ?? AppLayoutMode.horizontal.rawValue
        ) ?? .horizontal
        guard !layout.isVertical else { return false }

        // Don't touch events that already have Shift (user intentionally scrolling horizontally)
        guard !event.modifierFlags.contains(.shift) else { return false }

        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        // Only act when vertical component dominates
        guard abs(dy) > abs(dx), dy != 0 else { return false }

        // Route scrolling to the horizontal scroll view currently under the pointer.
        guard let scrollView = findHorizontalScrollView(at: event.locationInWindow) else { return false }

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

    /// BFS through the content view hierarchy to find the main **horizontally scrollable**
    /// NSScrollView. Validates that the document view is actually wider than the clip view
    /// (i.e. genuinely horizontally scrollable), preventing false matches from SwiftUI
    /// internal scroll views used by sheets, forms, popovers, etc.
    private func findHorizontalScrollView(at locationInWindow: NSPoint) -> NSScrollView? {
        // Validate cache: must still belong to this window, remain scrollable,
        // and still be under the current pointer location.
        if let sv = cachedScrollView, sv.window === self,
           sv.frame.width > 60,
           containsWindowPoint(locationInWindow, in: sv),
           isHorizontallyScrollable(sv) {
            return sv
        }

        cachedScrollView = nil
        guard let root = contentView else { return nil }
        var queue: [NSView] = [root]
        var hoveredScrollView: NSScrollView?
        var hoveredScore: CGFloat = .greatestFiniteMagnitude
        var bestScrollView: NSScrollView?
        var bestScore: CGFloat = 0
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let sv = view as? NSScrollView,
               sv.frame.width > 60,
               isHorizontallyScrollable(sv) {
                let areaScore = sv.frame.width * sv.frame.height

                if containsWindowPoint(locationInWindow, in: sv),
                   areaScore < hoveredScore {
                    hoveredScore = areaScore
                    hoveredScrollView = sv
                }

                if areaScore > bestScore {
                    bestScore = areaScore
                    bestScrollView = sv
                }
            }
            queue.append(contentsOf: view.subviews)
        }
        let resolvedScrollView = hoveredScrollView ?? bestScrollView
        cachedScrollView = resolvedScrollView
        return resolvedScrollView
    }

    /// A scroll view is "horizontally scrollable" when its document is wider than the visible clip.
    private func isHorizontallyScrollable(_ sv: NSScrollView) -> Bool {
        guard let documentWidth = sv.documentView?.frame.width else { return false }
        return documentWidth > sv.contentView.bounds.width + 1 // +1 for floating-point tolerance
    }

    private func containsWindowPoint(_ locationInWindow: NSPoint, in scrollView: NSScrollView) -> Bool {
        let localPoint = scrollView.convert(locationInWindow, from: nil)
        return scrollView.bounds.contains(localPoint)
    }
}
