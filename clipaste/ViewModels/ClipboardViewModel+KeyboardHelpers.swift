import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

extension ClipboardViewModel {
    var shouldRouteSearchArrowNavigation: Bool {
        guard panelFocusField == .searchBar else {
            return false
        }

        guard !displayedItemsForInteraction.isEmpty else {
            return false
        }

        guard !searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.hasMarkedText() {
            return false
        }

        return true
    }

    var hasActiveTextInputResponder: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }

        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }

        if responder is NSTextField {
            return true
        }

        return false
    }

    var shouldBlockKeyboardNavigationForQuickLook: Bool {
        isQuickLookActive && !isAutomaticPreviewActive
    }

    func matchesPanelShortcut(_ event: NSEvent, name: KeyboardShortcuts.Name) -> Bool {
        guard hasActiveTextInputResponder == false else {
            return false
        }

        guard let eventShortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return false
        }

        return name.shortcut == eventShortcut
    }

    func togglePanelLayoutShortcut() {
        let defaults = UserDefaults.standard
        let currentLayoutMode = AppLayoutMode(
            rawValue: defaults.string(forKey: "clipboardLayout") ?? AppLayoutMode.horizontal.rawValue
        ) ?? .horizontal

        let nextLayoutMode: AppLayoutMode
        switch currentLayoutMode {
        case .horizontal: nextLayoutMode = .vertical
        case .vertical:   nextLayoutMode = .compact
        case .compact:    nextLayoutMode = .horizontal
        }

        defaults.set(nextLayoutMode.rawValue, forKey: "clipboardLayout")
        defaults.set(nextLayoutMode.isVertical, forKey: "isVerticalLayout")
    }

    func isPlainNavigationEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return modifiers.isDisjoint(with: disallowedModifiers)
    }

    func navigationDirection(for keyCode: UInt16) -> Int? {
        let layout = AppLayoutMode(
            rawValue: UserDefaults.standard.string(forKey: "clipboardLayout") ?? AppLayoutMode.horizontal.rawValue
        ) ?? .horizontal

        if layout.isVertical {
            if keyCode == 125 {
                return 1
            }
            if keyCode == 126 {
                return -1
            }
        } else {
            if keyCode == 124 {
                return 1
            }
            if keyCode == 123 {
                return -1
            }
        }

        return nil
    }

    func acceptedSearchInput(from rawInput: String) -> String? {
        guard !rawInput.isEmpty else { return nil }
        guard rawInput.unicodeScalars.allSatisfy(isAllowedSearchScalar) else { return nil }
        return rawInput
    }

    func allowsShiftGeneratedTypeToSearch(
        modifiers: NSEvent.ModifierFlags,
        reservedModifiers: NSEvent.ModifierFlags,
        acceptedInput: String?
    ) -> Bool {
        guard modifiers == [.shift], reservedModifiers == [.shift] else {
            return false
        }

        guard let acceptedInput else {
            return false
        }

        return !acceptedInput.isEmpty
    }

    func isAllowedSearchScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value

        if (0xF700...0xF8FF).contains(value) {
            return false
        }

        if CharacterSet.controlCharacters.contains(scalar) {
            return false
        }

        switch scalar.properties.generalCategory {
        case .uppercaseLetter,
             .lowercaseLetter,
             .titlecaseLetter,
             .modifierLetter,
             .otherLetter,
             .decimalNumber,
             .letterNumber,
             .otherNumber,
             .connectorPunctuation,
             .dashPunctuation,
             .openPunctuation,
             .closePunctuation,
             .initialPunctuation,
             .finalPunctuation,
             .otherPunctuation,
             .mathSymbol,
             .currencySymbol,
             .modifierSymbol,
             .otherSymbol:
            return true
        default:
            return false
        }
    }

}
