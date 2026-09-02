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
