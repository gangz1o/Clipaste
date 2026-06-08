import SwiftUI

struct AIProviderIconView: View {
    let configuration: AIConfiguration
    var size: CGFloat = 14

    var body: some View {
        if let assetName = configuration.providerIconAssetName {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size, weight: .regular))
                .frame(width: size, height: size)
        }
    }
}

struct ClipboardAIBadgeView: View {
    var size: CGFloat = 22

    private var cornerRadius: CGFloat {
        size * 0.42
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(.sRGB, red: 1.00, green: 0.44, blue: 0.66, opacity: 1),
                Color(.sRGB, red: 0.56, green: 0.39, blue: 1.00, opacity: 1),
                Color(.sRGB, red: 0.19, green: 0.82, blue: 0.98, opacity: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(gradient.opacity(0.55), lineWidth: 0.8)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(gradient)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
