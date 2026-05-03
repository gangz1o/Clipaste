import AppKit
import SwiftUI

class AIConversationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AIConversationWindowManager: NSObject, NSWindowDelegate {
    static let shared = AIConversationWindowManager()

    private var openWindows: [String: NSWindow] = [:]

    private override init() {}

    func openConversation(
        title: String,
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) {
        let windowID = UUID().uuidString
        let conversationView = AIConversationView(
            windowID: windowID,
            title: title,
            configuration: configuration,
            initialMessages: messages
        )
        let hostingController = NSHostingController(rootView: conversationView)

        let window = AIConversationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = title.isEmpty ? String(localized: "AI Conversation") : title
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self

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
