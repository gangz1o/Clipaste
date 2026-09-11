import CoreGraphics

enum ClipboardPanelGeometry {
    /// AppKit screen coordinates are in points and may have negative origins on secondary displays.
    static func centeredFrame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let width = min(size.width, max(1, visibleFrame.width - margin * 2))
        let height = min(size.height, max(1, visibleFrame.height - margin * 2))

        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
