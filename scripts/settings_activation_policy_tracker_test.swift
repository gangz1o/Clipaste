import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func testNormalSettingsOpenArmsRestore() {
    var tracker = SettingsActivationPolicyTracker()

    let shouldPromote = tracker.noteSettingsRequested(
        usesAccessoryPolicy: true,
        currentPolicy: .accessory
    )

    expect(shouldPromote, "opening settings from accessory mode should promote to regular")
    expect(tracker.shouldRestoreAccessoryPolicy, "normal settings open should arm restore")
}

private func testSystemPresentedSettingsAlsoArmsRestore() {
    var tracker = SettingsActivationPolicyTracker()

    tracker.noteSettingsPresented(
        usesAccessoryPolicy: true,
        currentPolicy: .regular
    )

    expect(
        tracker.shouldRestoreAccessoryPolicy,
        "system-presented settings window should arm restore so Dock icon can disappear on close"
    )
}

private func testCloseRestoresOnlyAfterLastWindowCloses() {
    var tracker = SettingsActivationPolicyTracker()
    _ = tracker.noteSettingsRequested(
        usesAccessoryPolicy: true,
        currentPolicy: .accessory
    )

    let whileVisible = tracker.noteSettingsClosed(
        usesAccessoryPolicy: true,
        hasVisibleSettingsWindow: true
    )
    expect(!whileVisible, "visible settings window should block restore")
    expect(tracker.shouldRestoreAccessoryPolicy, "restore should stay armed while window remains visible")

    let afterClose = tracker.noteSettingsClosed(
        usesAccessoryPolicy: true,
        hasVisibleSettingsWindow: false
    )
    expect(afterClose, "closing the last settings window should restore accessory policy")
    expect(!tracker.shouldRestoreAccessoryPolicy, "restore should disarm after closing the last settings window")
}

private func testRegularAppsDoNotArmRestore() {
    var tracker = SettingsActivationPolicyTracker()

    let shouldPromote = tracker.noteSettingsRequested(
        usesAccessoryPolicy: false,
        currentPolicy: .regular
    )

    expect(!shouldPromote, "regular apps should not promote policy when opening settings")
    expect(!tracker.shouldRestoreAccessoryPolicy, "regular apps should not arm accessory restore")
}

@main
struct SettingsActivationPolicyTrackerTestRunner {
    static func main() {
        testNormalSettingsOpenArmsRestore()
        testSystemPresentedSettingsAlsoArmsRestore()
        testCloseRestoresOnlyAfterLastWindowCloses()
        testRegularAppsDoNotArmRestore()

        print("PASS")
    }
}
