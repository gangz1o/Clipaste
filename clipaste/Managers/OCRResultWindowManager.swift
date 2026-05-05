import AppKit
import SwiftUI

/// Window class that can become the key/main window — required for text selection &
/// keyboard input when the panel is summoned from a menu bar context.
final class OCRResultWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OCRResultWindowManager: NSObject, NSWindowDelegate {
    static let shared = OCRResultWindowManager()

    private var openWindows: [String: NSWindow] = [:]

    private override init() {}

    /// Open a new OCR result window for the given image. Each call creates its own
    /// window so multiple results can be inspected side-by-side.
    func openResult(imageData: Data, sourceTitle: String?) {
        let windowID = UUID().uuidString
        let view = OCRResultView(windowID: windowID, imageData: imageData, sourceTitle: sourceTitle)
        let hostingController = NSHostingController(rootView: view)

        let window = OCRResultWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = String(localized: "OCR Result")
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 340)

        openWindows[windowID] = window
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)

        TypeToSearchService.shared.isPaused = true
    }

    func close(windowID: String) {
        guard let window = openWindows[windowID] else { return }
        window.delegate = nil
        window.close()
        openWindows.removeValue(forKey: windowID)

        if openWindows.isEmpty {
            TypeToSearchService.shared.isPaused = false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowID = openWindows.first(where: { $0.value === window })?.key else {
            return
        }

        openWindows.removeValue(forKey: windowID)
        if openWindows.isEmpty {
            TypeToSearchService.shared.isPaused = false
        }
    }
}
