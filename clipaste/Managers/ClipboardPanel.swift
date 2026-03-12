import AppKit

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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

    /// Intercept all events before they are dispatched to views.
    /// If a scroll-wheel event is primarily vertical and the target is inside
    /// a horizontal-only NSScrollView, swap the axes so the user can scroll
    /// with a regular mouse wheel (no Shift required).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel,
           let redirected = verticalToHorizontalRedirect(for: event) {
            super.sendEvent(redirected)
            return
        }
        super.sendEvent(event)
    }

    private func verticalToHorizontalRedirect(for event: NSEvent) -> NSEvent? {
        // Don't touch events that already have Shift (user intentionally scrolling horizontally)
        guard !event.modifierFlags.contains(.shift) else { return nil }

        // Only redirect when the layout is horizontal
        let layout = UserDefaults.standard.string(forKey: "clipboardLayout") ?? "horizontal"
        guard layout == "horizontal" else { return nil }

        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        // Only act when vertical component dominates
        guard abs(dy) > abs(dx), dy != 0 else { return nil }

        guard let cgEvent = event.cgEvent?.copy() else { return nil }

        // --- Swap all three delta representations from Axis1 (vertical) → Axis2 (horizontal) ---

        // Integer deltas
        let intY = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: intY)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)

        // Point deltas
        let ptY = cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: ptY)
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)

        // FixedPt deltas (used by regular mice, Magic Mouse, and trackpad)
        let fixedY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedY)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)

        return NSEvent(cgEvent: cgEvent)
    }
}
