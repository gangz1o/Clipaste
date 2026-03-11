import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleClipboardPanel = Self(
        "toggleClipboardPanel",
        default: .init(.c, modifiers: [.command, .shift])
    )
}
