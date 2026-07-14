import AppKit
import SwiftUI

struct ScreenPinWindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard ScreenPinWindowInteractionPolicy.isWindowDragPoint(point, in: bounds) else {
                return nil
            }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
