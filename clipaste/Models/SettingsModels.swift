import AppKit
import Foundation
import SwiftUI

enum ModifierKey: String, CaseIterable, Identifiable {
    enum ShortcutRole {
        case quickPaste
        case plainText
    }

    case command
    case option
    case control
    case shift

    static let quickPasteDefaultsKey = "modifier_quick_paste"
    static let plainTextDefaultsKey = "modifier_plain_text"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    func localizedDisplayName(locale: Locale?) -> String {
        let resolved = locale ?? .current
        switch self {
        case .command: return String(localized: "Command", locale: resolved)
        case .option: return String(localized: "Option", locale: resolved)
        case .control: return String(localized: "Control", locale: resolved)
        case .shift: return String(localized: "Shift", locale: resolved)
        }
    }

    func pickerLabel(locale: Locale?) -> String {
        "\(symbol) \(localizedDisplayName(locale: locale))"
    }

    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    var eventModifiers: EventModifiers {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    static func migrateStoredPreferences(in defaults: UserDefaults = .standard) {
        migrate(defaultsKey: quickPasteDefaultsKey, fallback: .command, in: defaults)
        migrate(defaultsKey: plainTextDefaultsKey, fallback: .shift, in: defaults)
    }

    static func quickPastePreference(in defaults: UserDefaults = .standard) -> ModifierKey {
        resolvedValue(forKey: quickPasteDefaultsKey, fallback: .command, in: defaults)
    }

    static func plainTextPreference(in defaults: UserDefaults = .standard) -> ModifierKey {
        resolvedValue(forKey: plainTextDefaultsKey, fallback: .shift, in: defaults)
    }

    static func normalizedExclusiveShortcutPair(
        quickPaste: ModifierKey,
        plainText: ModifierKey,
        changedRole: ShortcutRole,
        previousQuickPaste: ModifierKey? = nil,
        previousPlainText: ModifierKey? = nil
    ) -> (quickPaste: ModifierKey, plainText: ModifierKey) {
        guard quickPaste == plainText else {
            return (quickPaste, plainText)
        }

        switch changedRole {
        case .quickPaste:
            return (
                quickPaste,
                replacementExcluding(
                    quickPaste,
                    preferred: previousPlainText
                )
            )
        case .plainText:
            return (
                replacementExcluding(
                    plainText,
                    preferred: previousQuickPaste
                ),
                plainText
            )
        }
    }

    private static func migrate(defaultsKey: String, fallback: ModifierKey, in defaults: UserDefaults) {
        let resolved = resolvedValue(forKey: defaultsKey, fallback: fallback, in: defaults)
        defaults.set(resolved.rawValue, forKey: defaultsKey)
    }

    private static func resolvedValue(
        forKey defaultsKey: String,
        fallback: ModifierKey,
        in defaults: UserDefaults
    ) -> ModifierKey {
        guard let storedValue = defaults.string(forKey: defaultsKey) else {
            return fallback
        }

        return Self(legacyRawValue: storedValue) ?? fallback
    }

    private init?(legacyRawValue: String) {
        switch legacyRawValue {
        case Self.command.rawValue, "⌘ Command":
            self = .command
        case Self.option.rawValue, "⌥ Option":
            self = .option
        case Self.control.rawValue, "⌃ Control":
            self = .control
        case Self.shift.rawValue, "⇧ Shift":
            self = .shift
        default:
            return nil
        }
    }

    private static func replacementExcluding(
        _ excluded: ModifierKey,
        preferred: ModifierKey?
    ) -> ModifierKey {
        if let preferred, preferred != excluded {
            return preferred
        }

        return allCases.first(where: { $0 != excluded }) ?? excluded
    }
}
