import CoreGraphics

// Run with: swiftc clipaste/Models/ClipboardPanelGeometry.swift scripts/ClipboardPanelGeometryTests.swift -o /tmp/ClipboardPanelGeometryTests && /tmp/ClipboardPanelGeometryTests
@main
enum ClipboardPanelGeometryTests {
    static func main() {
        let screens = [
            CGRect(x: 0, y: 38, width: 1440, height: 837),
            CGRect(x: -1920, y: 24, width: 1920, height: 1056),
            CGRect(x: 1440, y: -900, width: 1280, height: 876),
            CGRect(x: 0, y: 900, width: 2560, height: 1415),
            CGRect(x: -640, y: -480, width: 640, height: 456)
        ]

        for screen in screens {
            for width: CGFloat in [360, 740] {
                let size = CGSize(width: width, height: 700)
                let frame = ClipboardPanelGeometry.centeredFrame(size: size, visibleFrame: screen)
                precondition(abs(frame.midX - screen.midX) < 0.001, "Must center on the selected display")
                precondition(abs(frame.midY - screen.midY) < 0.001, "Must center above the Dock and below the menu bar")
                precondition(screen.insetBy(dx: 12, dy: 12).contains(frame), "Panel must remain within the visible area")
                precondition(frame.width <= size.width && frame.height <= size.height, "Must not enlarge the panel")
                if screen.width >= size.width + 24 && screen.height >= size.height + 24 {
                    precondition(frame.size == size, "Normal displays must preserve list and preview dimensions")
                }
            }
        }

        print("ClipboardPanelGeometryTests passed (5 display arrangements, with and without preview)")
    }
}
