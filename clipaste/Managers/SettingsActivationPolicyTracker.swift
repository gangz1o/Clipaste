enum SettingsActivationPolicy {
    case regular
    case accessory
}

struct SettingsActivationPolicyTracker {
    private(set) var shouldRestoreAccessoryPolicy = false

    mutating func noteSettingsRequested(
        usesAccessoryPolicy: Bool,
        currentPolicy: SettingsActivationPolicy
    ) -> Bool {
        guard usesAccessoryPolicy else { return false }
        guard currentPolicy == .accessory else { return false }

        shouldRestoreAccessoryPolicy = true
        return true
    }

    mutating func noteSettingsPresented(
        usesAccessoryPolicy: Bool,
        currentPolicy: SettingsActivationPolicy
    ) {
        guard usesAccessoryPolicy else { return }
        guard currentPolicy == .regular else { return }

        shouldRestoreAccessoryPolicy = true
    }

    mutating func noteSettingsClosed(
        usesAccessoryPolicy: Bool,
        hasVisibleSettingsWindow: Bool
    ) -> Bool {
        guard shouldRestoreAccessoryPolicy else { return false }
        guard usesAccessoryPolicy else {
            shouldRestoreAccessoryPolicy = false
            return false
        }
        guard !hasVisibleSettingsWindow else { return false }

        shouldRestoreAccessoryPolicy = false
        return true
    }
}
