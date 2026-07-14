import AppKit
import SwiftUI

private struct RuntimeHarnessView: View {
    var body: some View {
        Color.blue
            .frame(width: 240, height: 240)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white, lineWidth: 6)
            }
            .clipShape(.rect(cornerRadius: 16))
            .shadow(radius: 6)
            .onDrag {
                NSItemProvider(object: "parent" as NSString)
            }
            .overlay(alignment: .topLeading) {
                ScreenPinIconDragTarget(isActive: true) { point in
                    try? "\(point.x),\(point.y)".write(
                        to: URL(fileURLWithPath: "/tmp/screen-pin-drag-runtime-result"),
                        atomically: true,
                        encoding: .utf8
                    )
                    NSApplication.shared.terminate(nil)
                }
                .frame(width: 52, height: 52)
                .padding(.leading, 8)
            }
            .onHover { _ in }
            .simultaneousGesture(TapGesture().onEnded {})
    }
}

@main
@MainActor
enum ScreenPinDragRuntimeHarness {
    static func main() {
        try? FileManager.default.removeItem(atPath: "/tmp/screen-pin-drag-runtime-result")

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 240, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: RuntimeHarnessView())
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)

        window.contentView?.layoutSubtreeIfNeeded()
        if let contentView = window.contentView,
           let dragSource = descendants(of: contentView)
            .first(where: { $0 is ScreenPinDragSourceView.DragSourceView }) {
            let targetInWindow = dragSource.convert(dragSource.bounds, to: nil)
            let targetOrigin = window.convertPoint(toScreen: targetInWindow.origin)
            print(
                "TARGET \(targetOrigin.x),\(targetOrigin.y),"
                    + "\(targetInWindow.width),\(targetInWindow.height)"
            )
        }

        print("READY \(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        application.run()
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
