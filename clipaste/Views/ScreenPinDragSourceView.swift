import AppKit
import SwiftUI

struct ScreenPinDragSourceView: NSViewRepresentable {
    let onDragEnded: (CGPoint) -> Void

    @Environment(\.locale) private var locale

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.onDragEnded = onDragEnded
        configureAccessibility(for: view)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.onDragEnded = onDragEnded
        configureAccessibility(for: nsView)
    }

    private func configureAccessibility(for view: DragSourceView) {
        view.onActivate = {
            onDragEnded(NSEvent.mouseLocation)
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(
            String(localized: "Drag to Pin on Screen", locale: locale)
        )
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var onDragEnded: ((CGPoint) -> Void)?
        var onActivate: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        private static let pasteboardType = NSPasteboard.PasteboardType(
            "com.gangz1o.clipaste.screen-pin"
        )
        private var mouseDownEvent: NSEvent?
        private var hasStartedDragging = false

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            mouseDownEvent = event
            hasStartedDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard hasStartedDragging == false, let mouseDownEvent else { return }

            let start = mouseDownEvent.locationInWindow
            let current = event.locationInWindow
            guard hypot(current.x - start.x, current.y - start.y) >= 3 else { return }

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(UUID().uuidString, forType: Self.pasteboardType)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let previewSize = CGSize(width: 36, height: 36)
            let localPoint = convert(current, from: nil)
            let previewFrame = CGRect(
                x: localPoint.x - previewSize.width / 2,
                y: localPoint.y - previewSize.height / 2,
                width: previewSize.width,
                height: previewSize.height
            )
            let previewImage = NSImage(
                systemSymbolName: "photo.fill",
                accessibilityDescription: nil
            )
            draggingItem.setDraggingFrame(previewFrame, contents: previewImage)

            hasStartedDragging = true
            let session = beginDraggingSession(
                with: [draggingItem],
                event: event,
                source: self
            )
            session.animatesToStartingPositionsOnCancelOrFail = false
        }

        override func mouseUp(with event: NSEvent) {
            resetDragState()
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }

        override func keyDown(with event: NSEvent) {
            guard event.keyCode == 36 || event.keyCode == 49 else {
                super.keyDown(with: event)
                return
            }
            onActivate?()
        }

        override func accessibilityPerformPress() -> Bool {
            onActivate?()
            return true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .generic
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let releasePoint = NSEvent.mouseLocation
            resetDragState()
            onDragEnded?(releasePoint)
        }

        private func resetDragState() {
            mouseDownEvent = nil
            hasStartedDragging = false
        }
    }
}
