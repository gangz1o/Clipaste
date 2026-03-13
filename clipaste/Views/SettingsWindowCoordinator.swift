import AppKit
import SwiftUI

enum SettingsWindowCoordinator {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("clipaste.settings.window")
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private static var shouldRestoreAccessoryPolicy = false

    @MainActor
    static func open(using openSettings: @escaping () -> Void) {
        promoteToRegularIfNeeded()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            openSettings()
            bringToFrontSoon()
        }
    }

    @MainActor
    static func register(window: NSWindow) {
        window.identifier = windowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
        attachCloseObserver(to: window)
    }

    @MainActor
    private static func promoteToRegularIfNeeded() {
        guard shouldUseAccessoryPolicy else { return }
        guard NSApp.activationPolicy() == .accessory else { return }

        shouldRestoreAccessoryPolicy = true
        NSApp.setActivationPolicy(.regular)
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

    @MainActor
    private static func attachCloseObserver(to window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard closeObservers[windowID] == nil else { return }

        closeObservers[windowID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                removeCloseObserver(for: window)
                DispatchQueue.main.async {
                    restoreAccessoryPolicyIfNeeded()
                }
            }
        }
    }

    @MainActor
    private static func removeCloseObserver(for window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard let observer = closeObservers.removeValue(forKey: windowID) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    @MainActor
    private static func restoreAccessoryPolicyIfNeeded() {
        guard shouldRestoreAccessoryPolicy else { return }
        guard shouldUseAccessoryPolicy else {
            shouldRestoreAccessoryPolicy = false
            return
        }

        let hasVisibleSettingsWindow = NSApp.windows.contains {
            $0.identifier == windowIdentifier && $0.isVisible
        }

        guard !hasVisibleSettingsWindow else { return }

        NSApp.setActivationPolicy(.accessory)
        shouldRestoreAccessoryPolicy = false
    }

    private static var shouldUseAccessoryPolicy: Bool {
        UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
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

struct WindowAppearanceObserver: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        TrackingView(theme: theme)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        trackingView.update(theme: theme)
    }

    private final class TrackingView: NSView {
        private var theme: AppTheme

        init(theme: AppTheme) {
            self.theme = theme
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTheme()
        }

        func update(theme: AppTheme) {
            self.theme = theme
            applyTheme()
        }

        private func applyTheme() {
            window?.appearance = theme.nsAppearance
        }
    }
}
