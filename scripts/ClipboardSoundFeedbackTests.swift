import Foundation

@main
enum ClipboardSoundFeedbackTests {
    @MainActor
    static func main() {
        let suite = "ClipboardSoundFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(ClipboardSoundFeedback.isEnabled(defaults: defaults))
        defaults.set(false, forKey: "playSound")
        precondition(!ClipboardSoundFeedback.isEnabled(defaults: defaults), "Legacy opt-out must be respected before settings open")
        defaults.set(true, forKey: "isCopySoundEnabled")
        precondition(ClipboardSoundFeedback.isEnabled(defaults: defaults), "Current setting overrides legacy value")
        defaults.set(false, forKey: "isCopySoundEnabled")
        precondition(!ClipboardSoundFeedback.isEnabled(defaults: defaults))
        var count = 0
        ClipboardSoundFeedback.play(defaults: defaults, changeCount: 1) { count += 1 }
        precondition(count == 0, "Disabled sound must not play")
        defaults.set(true, forKey: "isCopySoundEnabled")
        ClipboardSoundFeedback.play(defaults: defaults, changeCount: 2) { count += 1 }
        ClipboardSoundFeedback.play(defaults: defaults, changeCount: 2) { count += 1 }
        precondition(count == 1, "Manual copy and monitor must not sound twice for the same change")
        ClipboardSoundFeedback.play(defaults: defaults, changeCount: 3) { count += 1 }
        precondition(count == 2, "A later copy must play again")
        print("ClipboardSoundFeedbackTests passed")
    }
}
