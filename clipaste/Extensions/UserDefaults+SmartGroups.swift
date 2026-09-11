import Foundation

extension UserDefaults {
    @objc dynamic var enable_smart_groups: Bool {
        // Match the settings toggle when the user has never explicitly saved this preference.
        // bool(forKey:) would emit false on the initial KVO event for a missing key.
        object(forKey: "enable_smart_groups") as? Bool ?? true
    }
}
