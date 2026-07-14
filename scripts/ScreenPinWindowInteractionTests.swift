import AppKit

@main
enum ScreenPinWindowInteractionTests {
    static func main() {
        verifyConstraintRefreshDeferral()
        verifyResizeBorderHitTesting()
        print("ScreenPinWindowInteractionTests passed")
    }

    private static func verifyConstraintRefreshDeferral() {
        var policy = ScreenPinWindowInteractionPolicy()

        precondition(
            policy.screenDidChange(isLiveResize: true) == false,
            "screen changes must not mutate constraints during live resize"
        )
        precondition(policy.hasDeferredConstraintRefresh)
        precondition(
            policy.liveResizeDidEnd(),
            "ending live resize must consume the deferred refresh"
        )
        precondition(policy.hasDeferredConstraintRefresh == false)
        precondition(policy.liveResizeDidEnd() == false)
        precondition(policy.screenDidChange(isLiveResize: false))
    }

    private static func verifyResizeBorderHitTesting() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)

        precondition(
            ScreenPinWindowInteractionPolicy.isWindowDragPoint(
                CGPoint(x: 160, y: 100),
                in: bounds
            )
        )
        precondition(
            ScreenPinWindowInteractionPolicy.isWindowDragPoint(
                CGPoint(x: 3, y: 100),
                in: bounds
            ) == false,
            "left resize edge must be reserved for AppKit"
        )
        precondition(
            ScreenPinWindowInteractionPolicy.isWindowDragPoint(
                CGPoint(x: 317, y: 100),
                in: bounds
            ) == false,
            "right resize edge must be reserved for AppKit"
        )
        precondition(
            ScreenPinWindowInteractionPolicy.isWindowDragPoint(
                CGPoint(x: 160, y: 4),
                in: bounds
            ) == false,
            "bottom resize edge must be reserved for AppKit"
        )
        precondition(
            ScreenPinWindowInteractionPolicy.isWindowDragPoint(
                CGPoint(x: 160, y: 197),
                in: bounds
            ) == false,
            "top resize edge must be reserved for AppKit"
        )
    }
}
