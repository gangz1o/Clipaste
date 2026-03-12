import AppKit
import SwiftUI

enum SettingsWindowCoordinator {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("clipaste.settings.window")

    @MainActor
    static func open(using openSettings: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringToFrontSoon()
    }

    @MainActor
    static func register(window: NSWindow) {
        window.identifier = windowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    @MainActor
    private static func bringToFrontSoon() {
        let delays: [TimeInterval] = [0, 0.05, 0.2]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                bringToFrontIfPossible()
            }
        }
    }

    @MainActor
    private static func bringToFrontIfPossible() {
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.identifier == windowIdentifier }) else {
            return
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard let window else { return }
            Task { @MainActor in
                SettingsWindowCoordinator.register(window: window)
            }
        }
    }
}
