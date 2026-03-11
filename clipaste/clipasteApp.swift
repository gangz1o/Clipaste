import SwiftUI
import AppKit
import KeyboardShortcuts
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingDefaultsKey = "hasCompletedOnboarding"
    private var onboardingStateObserver: NSObjectProtocol?
    private var lastKnownOnboardingState = false
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm the panel so the first global shortcut does not block on panel construction.
        _ = ClipboardPanelManager.shared

        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        lastKnownOnboardingState = hasCompleted
        updateActivationPolicy(hasCompletedOnboarding: hasCompleted)

        if !hasCompleted {
            presentOnboardingWindow()
        }

        // Register the global shortcut in AppDelegate instead of any SwiftUI lifecycle path.
        KeyboardShortcuts.onKeyDown(for: .toggleClipboardPanel) { [weak self] in
            self?.handleTogglePanelShortcut()
        }

        // Verify accessibility permission so KeyboardShortcuts can use the privileged
        // CGEventTap (session-level) instead of the degraded NSEvent global monitor.
        // Without this, apps like Xcode that handle ⌘⇧C internally will swallow the
        // event before our monitor sees it.
        checkAndRequestAccessibility()

        onboardingStateObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: self.onboardingDefaultsKey)
            guard hasCompletedOnboarding != self.lastKnownOnboardingState else { return }

            self.lastKnownOnboardingState = hasCompletedOnboarding
            self.updateActivationPolicy(hasCompletedOnboarding: hasCompletedOnboarding)

            if hasCompletedOnboarding {
                self.dismissOnboardingWindow()
            } else {
                self.presentOnboardingWindow()
            }
        }
    }

    private func handleTogglePanelShortcut() {
        ClipboardPanelManager.shared.togglePanel()
    }

    /// Ensures the privileged CGEventTap (session-level) is available.
    /// Without Accessibility permission, KeyboardShortcuts falls back to
    /// NSEvent.addGlobalMonitorForEvents which is blocked by apps like Xcode
    /// that handle the key event internally before it propagates.
    private func checkAndRequestAccessibility() {
        // Attempt to obtain the trusted status.  Passing `prompt: true` makes
        // macOS immediately show the "clipaste wants to control this computer"
        // system dialog so the user can grant access in one click.
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            // Permission already granted – KeyboardShortcuts will use the
            // privileged tap automatically; nothing more to do.
            return
        }

        // Permission was just requested.  Re-register the shortcut after a
        // short delay so KeyboardShortcuts can retry with the privileged tap
        // once the user grants access (the library re-creates the tap on the
        // next registration call).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            KeyboardShortcuts.onKeyDown(for: .toggleClipboardPanel) { [weak self] in
                self?.handleTogglePanelShortcut()
            }
        }
    }

    deinit {
        if let onboardingStateObserver {
            NotificationCenter.default.removeObserver(onboardingStateObserver)
        }
    }

    private func updateActivationPolicy(hasCompletedOnboarding: Bool) {
        if hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func presentOnboardingWindow() {
        let window = onboardingWindow ?? makeOnboardingWindow()
        onboardingWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOnboardingWindow() {
        onboardingWindow?.orderOut(nil)
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func makeOnboardingWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "Clipaste"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()

        window.delegate = self
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil
    }
}

@main
struct clipasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsViewModel = SettingsViewModel()
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some Scene {
        // Register standard macOS Settings Window
        Settings {
            SettingsView()
                .environmentObject(settingsViewModel)
                .modelContainer(StorageManager.shared.container)
                .environment(\.locale, appLanguage.locale ?? .current)
        }

        // Status Bar Menu to access app functions
        MenuBarExtra("Clipaste", image: "MenuBarIcon") {
            Group {
                Button("设置...") {
                    // macOS native way to open the Settings window programmatically
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button("退出 Clipaste") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .modelContainer(StorageManager.shared.container)
        }
    }
}
