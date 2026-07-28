import SwiftUI

struct ClipboardFavoriteButtonStyle: ButtonStyle {
    let isFavorite: Bool
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFavorite || configuration.isPressed ? accentColor : Color.secondary)
            .background {
                Circle()
                    .fill(
                        accentColor.opacity(
                            configuration.isPressed ? 0.18 : (isFavorite ? 0.10 : 0)
                        )
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
