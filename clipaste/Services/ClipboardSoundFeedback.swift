import AppKit

@MainActor
enum ClipboardSoundFeedback {
    private static var lastPlayedChangeCount: Int?

    static func isEnabled(defaults: UserDefaults) -> Bool {
        // Preserve the current preference and pre-migration legacy installations.
        defaults.object(forKey: "isCopySoundEnabled") as? Bool
            ?? defaults.object(forKey: "playSound") as? Bool
            ?? true
    }

    static func play(
        defaults: UserDefaults,
        changeCount: Int = NSPasteboard.general.changeCount,
        perform: () -> Void = { NSSound(named: "Pop")?.play() }
    ) {
        guard isEnabled(defaults: defaults), lastPlayedChangeCount != changeCount else { return }
        lastPlayedChangeCount = changeCount
        perform()
    }
}
