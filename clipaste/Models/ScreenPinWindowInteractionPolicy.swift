import CoreGraphics

struct ScreenPinWindowInteractionPolicy {
    static let resizeBorderWidth: CGFloat = 8

    private(set) var hasDeferredConstraintRefresh = false

    mutating func screenDidChange(isLiveResize: Bool) -> Bool {
        guard isLiveResize else { return true }
        hasDeferredConstraintRefresh = true
        return false
    }

    mutating func liveResizeDidEnd() -> Bool {
        defer { hasDeferredConstraintRefresh = false }
        return hasDeferredConstraintRefresh
    }

    static func isWindowDragPoint(
        _ point: CGPoint,
        in bounds: CGRect,
        resizeBorderWidth: CGFloat = resizeBorderWidth
    ) -> Bool {
        guard resizeBorderWidth >= 0 else { return false }
        let dragRegion = bounds.insetBy(dx: resizeBorderWidth, dy: resizeBorderWidth)
        guard dragRegion.width > 0, dragRegion.height > 0 else { return false }
        return dragRegion.contains(point)
    }
}
