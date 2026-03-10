import SwiftUI
import KeyboardShortcuts
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingDefaultsKey = "hasCompletedOnboarding"
    private var onboardingStateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)

        if !hasCompleted {
            // 引导模式：显示 Dock 图标，允许正常弹窗并获取强焦点
            NSApp.setActivationPolicy(.regular)
            // 强制前台激活
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 正常模式：纯后台运行，隐藏 Dock 图标
            NSApp.setActivationPolicy(.accessory)
        }

        // Initialize the panel manager
        _ = ClipboardPanelManager.shared
        
        // Listen for the global shortcut to toggle the clipboard panel
        KeyboardShortcuts.onKeyUp(for: .toggleClipboardPanel) {
            ClipboardPanelManager.shared.togglePanel()
        }

        onboardingStateObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: self.onboardingDefaultsKey)
            self.updateActivationPolicy(hasCompletedOnboarding: hasCompletedOnboarding)
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
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            }
        }
    }
}

@main
struct clipasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            if !hasCompletedOnboarding {
                OnboardingView()
            }
        }
        .windowStyle(.hiddenTitleBar)

        // Register standard macOS Settings Window
        Settings {
            SettingsView()
                .environmentObject(settingsViewModel)
                .modelContainer(StorageManager.shared.container)
        }
        
        // Status Bar Menu to access app functions
        MenuBarExtra("Clipaste", systemImage: "doc.on.clipboard") {
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
