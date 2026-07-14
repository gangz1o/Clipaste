import AppKit
import SwiftUI

private struct DragHitTestView: View {
    var body: some View {
        Color.blue
            .frame(width: 240, height: 240)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white, lineWidth: 6)
            }
            .clipShape(.rect(cornerRadius: 16))
            .shadow(radius: 6)
            .onHover { _ in }
            .onDrag {
                NSItemProvider(object: "parent" as NSString)
            }
            .overlay(alignment: .topLeading) {
                ScreenPinIconDragTarget(isActive: true) { _ in }
                    .frame(width: 52, height: 52)
                    .padding(.leading, 8)
            }
            .simultaneousGesture(TapGesture().onEnded {})
    }
}

@main
@MainActor
enum ScreenPinDragHitTest {
    static func main() {
        let host = NSHostingView(rootView: DragHitTestView())
        host.frame = CGRect(x: 0, y: 0, width: 240, height: 240)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()

        guard let dragSource = descendants(of: host)
            .first(where: { $0 is ScreenPinDragSourceView.DragSourceView }) else {
            fatalError("Drag source NSView was not mounted")
        }

        precondition(dragSource.frame.width >= 27, "drag source must fill the handle width")
        precondition(dragSource.frame.height >= 27, "drag source must fill the handle height")

        precondition(dragSource.frame.width >= 51, "drag source must fill the source app icon")
        precondition(dragSource.frame.height >= 51, "drag source must fill the source app icon")

        let hitView = host.hitTest(CGPoint(x: 34, y: 214))
        precondition(hitView === dragSource, "drag source must win hit testing over the parent drag")
        print("ScreenPinDragHitTest passed")
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
