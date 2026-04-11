import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleClipboardPanel = Self(
        "toggleClipboardPanel",
        default: .init(.c, modifiers: [.command, .shift])
    )

    static let toggleVerticalClipboard = Self(
        "toggleVerticalClipboard",
        default: .init(.t, modifiers: [.command, .shift])
    )

    static let nextList = Self(
        "nextList",
        default: .init(.rightArrow, modifiers: [.command])
    )

    static let prevList = Self(
        "prevList",
        default: .init(.leftArrow, modifiers: [.command])
    )

    static let clearHistory = Self(
        "clearHistory",
        default: .init(.r, modifiers: [.command, .shift])
    )

    static let toggleFavoriteSelection = Self(
        "toggleFavoriteSelection",
        default: .init(.e, modifiers: [.control])
    )
}
