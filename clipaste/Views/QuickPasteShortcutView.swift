import SwiftUI

struct QuickPasteShortcutBadge: View {
    let modifierKey: ModifierKey
    let number: Int
    var color: Color = .secondary

    var body: some View {
        Text("\(modifierKey.symbol) \(number)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .allowsHitTesting(false)
    }
}

struct QuickPasteShortcutHost: View {
    let shortcutIndex: Int
    let modifierKey: ModifierKey
    let plainTextModifierKey: ModifierKey?
    let action: () -> Void
    let plainTextAction: (() -> Void)?

    var body: some View {
        ZStack {
            shortcutButton(
                modifiers: modifierKey.eventModifiers,
                action: action
            )

            if let plainTextAction,
               let combinedModifiers = combinedPlainTextModifiers {
                shortcutButton(
                    modifiers: combinedModifiers,
                    action: plainTextAction
                )
            }
        }
    }

    private var combinedPlainTextModifiers: EventModifiers? {
        guard let plainTextModifierKey else {
            return nil
        }

        let combined = modifierKey.eventModifiers.union(plainTextModifierKey.eventModifiers)
        return combined == modifierKey.eventModifiers ? nil : combined
    }

    private func shortcutButton(
        modifiers: EventModifiers,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(
            KeyEquivalent(Character(String(shortcutIndex + 1))),
            modifiers: modifiers
        )
        .opacity(0.001)
        .accessibilityHidden(true)
    }
}
