import SwiftUI

struct ClipboardFavoriteButton: View {
    let isFavorite: Bool
    let accentColor: Color
    let action: () -> Void

    private var label: LocalizedStringKey {
        isFavorite ? "Remove from Favorites" : "Add to Favorites"
    }

    private var systemImage: String {
        isFavorite ? "star.fill" : "star"
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(.circle)
        }
        .buttonStyle(
            ClipboardFavoriteButtonStyle(
                isFavorite: isFavorite,
                accentColor: accentColor
            )
        )
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}
