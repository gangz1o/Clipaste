import AppKit
import SwiftUI

enum AppLanguage: String {
    case auto

    var resolvedLocale: Locale { .current }
}

@main
@MainActor
enum ScreenPinResizeRuntimeHarness {
    private static var controller: ScreenPinWindowController?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let image = NSImage(size: CGSize(width: 1_200, height: 800))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1_200, height: 800)).fill()
        image.unlockFocus()

        controller = ScreenPinWindowController(
            id: UUID(),
            image: image,
            screenPoint: CGPoint(x: 600, y: 500),
            initialSizeScale: 1
        ) { _ in
            application.terminate(nil)
        }
        controller?.show()
        application.activate(ignoringOtherApps: true)

        print("READY \(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        application.run()
    }
}
