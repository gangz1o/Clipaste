import Cocoa
import ApplicationServices

enum AccessibilityPermissionCoordinator {
    @discardableResult
    static func requestPermissionPrompt() -> Bool {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func openSystemSettings() -> Bool {
        let isAlreadyTrusted = requestPermissionPrompt()
        primeAccessibilityRegistration()

        if isAlreadyTrusted {
            return openAccessibilitySettingsPane()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            _ = openAccessibilitySettingsPane()
        }
        return true
    }

    private static func primeAccessibilityRegistration() {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApplication: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplication
        )
    }

    private static func openAccessibilitySettingsPane() -> Bool {
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
