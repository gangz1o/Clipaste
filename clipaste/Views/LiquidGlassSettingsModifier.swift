import SwiftUI

/// macOS 26 Liquid Glass Card Modifier for Settings Panels
struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
}

extension View {
    /// Applies a premium Liquid Glass card style suitable for modern macOS interfaces.
    func liquidGlassCard() -> some View {
        self.modifier(LiquidGlassCardModifier())
    }
}

/// Settings Section Title Modifier
struct SettingsSectionTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold, design: .default))
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
            .padding(.leading, 4)
    }
}

extension View {
    /// Applies the standard font styling for a settings section header.
    func settingsSectionTitle() -> some View {
        self.modifier(SettingsSectionTitleModifier())
    }
}
