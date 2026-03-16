import Cocoa

enum AccessibilityPermissionCoordinator {
    static func requestPermissionPrompt() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func openSystemSettings() -> Bool {
        requestPermissionPrompt()

        let workspace = NSWorkspace.shared
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Assistive",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ].compactMap(URL.init(string:))

        for url in candidateURLs where workspace.open(url) {
            return true
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        return workspace.open(fallbackURL)
    }
}

extension SettingsViewModel {
    func requestAccessibilityPermission() {
        AccessibilityPermissionCoordinator.requestPermissionPrompt()
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionCoordinator.openSystemSettings()
    }
}
