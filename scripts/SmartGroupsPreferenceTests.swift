import Combine
import Foundation

// Run with: swiftc clipaste/Extensions/UserDefaults+SmartGroups.swift scripts/SmartGroupsPreferenceTests.swift -o /tmp/SmartGroupsPreferenceTests && /tmp/SmartGroupsPreferenceTests
@main
enum SmartGroupsPreferenceTests {
    static func main() {
        let suiteName = "Clipaste.SmartGroupsPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "enable_smart_groups"
        precondition(defaults.object(forKey: key) == nil)
        precondition(defaults.enable_smart_groups, "An unset preference must default to enabled")

        var observedValues: [Bool] = []
        let subscription = defaults.publisher(for: \.enable_smart_groups)
            .sink { observedValues.append($0) }
        defer { subscription.cancel() }
        precondition(observedValues == [true], "Initial KVO delivery must agree with the enabled settings default")
        precondition(defaults.object(forKey: key) == nil, "Reading the default must not persist a user choice")

        for isEnabled in [false, true, false] {
            defaults.set(isEnabled, forKey: key)
            precondition(defaults.enable_smart_groups == isEnabled, "Must respect an explicit choice")
            precondition(observedValues.last == isEnabled, "Toggling must reach the panel subscription")

            // A new observer, as created on launch, must retain both explicit on and off choices.
            let reopenedDefaults = UserDefaults(suiteName: suiteName)!
            var initialValue: Bool?
            let reopenedSubscription = reopenedDefaults.publisher(for: \.enable_smart_groups)
                .sink { initialValue = $0 }
            precondition(initialValue == isEnabled, "A new subscription must preserve the saved preference")
            reopenedSubscription.cancel()
        }

        defaults.removeObject(forKey: key)
        precondition(defaults.enable_smart_groups, "Removing the setting must restore the enabled default")
        precondition(observedValues.last == true, "Resetting the setting must update observers to enabled")

        print("SmartGroupsPreferenceTests passed")
    }
}
