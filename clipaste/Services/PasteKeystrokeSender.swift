import CoreGraphics
import Foundation

@MainActor
enum PasteKeystrokeSender {
    /// Use native Ctrl+V in Windows App to avoid relying on its Cmd shortcut mapping.
    /// Both the current app and the older Microsoft Remote Desktop use this bundle identifier.
    static func usesWindowsPasteShortcut(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.microsoft.rdc.macos"
    }

    @discardableResult
    static func send(
        bundleIdentifier: String?,
        isTargetActive: () -> Bool,
        currentModifiers: () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) },
        postEvent: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> Bool {
        let isWindowsApp = usesWindowsPasteShortcut(bundleIdentifier: bundleIdentifier)
        let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]

        do {
            // Allow focus restoration and give the remote client time to notice the new clipboard.
            try await sleep(.milliseconds(isWindowsApp ? 150 : 60))
            for _ in 0..<100 {
                try Task.checkCancellation()
                if isTargetActive(), currentModifiers().intersection(shortcutModifiers).isEmpty {
                    return await postKeystroke(
                        isWindowsApp: isWindowsApp,
                        isTargetActive: isTargetActive,
                        postEvent: postEvent,
                        sleep: sleep
                    )
                }
                // Quick-paste can be triggered while Command/Option/Shift is still physically held.
                try await sleep(.milliseconds(20))
            }
        } catch {
            // A cancelled paste must not fire later into a different window.
        }
        return false
    }

    private static func postKeystroke(
        isWindowsApp: Bool,
        isTargetActive: () -> Bool,
        postEvent: (CGEvent) -> Void,
        sleep: (Duration) async throws -> Void
    ) async -> Bool {
        let modifierKey: CGKeyCode = isWindowsApp ? 0x3B : 0x37 // Left Control / Command
        let flags: CGEventFlags = isWindowsApp ? .maskControl : .maskCommand
        // Keep synthetic modifier state separate from the user's physical keyboard state.
        guard let source = CGEventSource(stateID: .privateState),
              let modifierDown = CGEvent(keyboardEventSource: source, virtualKey: modifierKey, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let modifierUp = CGEvent(keyboardEventSource: source, virtualKey: modifierKey, keyDown: false) else {
            return false
        }
        // Remote clients need actual modifier transitions, not just flags attached to V.
        modifierDown.type = .flagsChanged
        modifierDown.flags = flags
        vDown.flags = flags
        vUp.flags = flags
        modifierUp.type = .flagsChanged
        modifierUp.flags = []

        guard !Task.isCancelled, isTargetActive() else { return false }
        postEvent(modifierDown)
        var pressedV = false
        defer {
            // Always balance pressed keys, including cancellation or focus loss between events.
            if pressedV { postEvent(vUp) }
            postEvent(modifierUp)
        }
        do {
            try await sleep(.milliseconds(10))
            try Task.checkCancellation()
            guard isTargetActive() else { return false }
            postEvent(vDown)
            pressedV = true
            try await sleep(.milliseconds(10))
            return true
        } catch {
            return false
        }
    }
}
