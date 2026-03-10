import Foundation
import Combine
import ServiceManagement
import Cocoa

/// Defines the behavior after selecting a clipboard item
enum PasteBehavior: String, CaseIterable, Identifiable {
    case direct = "Direct Paste to Current App"
    case clipboardOnly = "Copy to Clipboard Only"
    
    var id: String { self.rawValue }
}

/// Defines the retention policy for clipboard history
enum HistoryLimit: String, CaseIterable, Identifiable {
    case day = "1 Day"
    case week = "1 Week"
    case month = "1 Month"
    case year = "1 Year"
    case unlimited = "Unlimited"
    
    var id: String { self.rawValue }
}

/// Defines the visual layout style of the main clipboard interface
enum AppLayoutMode: String, CaseIterable, Identifiable {
    case horizontal = "Horizontal Cards"
    case vertical = "Vertical List"
    
    var id: String { self.rawValue }
}

final class SettingsViewModel: ObservableObject {
    
    func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                print("Successfully registered for launch at login.")
            } else {
                try service.unregister()
                print("Successfully unregistered from launch at login.")
            }
        } catch {
            print("Failed to update launch at login status: \(error)")
        }
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("User needs to grant Accessibility permission in System Settings.")
            // Open System Settings -> Privacy & Security -> Accessibility
            // Usually, `AXIsProcessTrustedWithOptions` with prompt: true will open the dialog for the user natively.
        } else {
            print("Accessibility permission already granted.")
        }
    }
}
