import SwiftUI


struct AppearanceThemePreview: View {
    let theme: AppTheme
    let isSelected: Bool
    let accentColor: Color

    private enum PreviewWindowStyle {
        case light
        case dark
    }

    private let previewSize = CGSize(width: 86, height: 50)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(previewSurfaceFill)

            if theme == .system {
                systemCompositePreview
            } else {
                previewWindow(
                    style: theme == .dark ? .dark : .light,
                    size: previewSize,
                    compact: false
                )
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? accentColor : previewSurfaceBorder,
                    lineWidth: isSelected ? 3.5 : 0.8
                )
        }
        .shadow(
            color: isSelected ? accentColor.opacity(0.12) : .black.opacity(0.08),
            radius: isSelected ? 8 : 5,
            y: isSelected ? 3 : 2
        )
        .animation(.snappy(duration: 0.18), value: isSelected)
    }

    private var systemCompositePreview: some View {
        ZStack {
            previewWindow(
                style: .light,
                size: CGSize(width: 44, height: 36),
                compact: true
            )
            .offset(x: -12, y: 2)

            previewWindow(
                style: .dark,
                size: CGSize(width: 44, height: 36),
                compact: true
            )
            .offset(x: 12, y: -2)
        }
    }

    private var previewSurfaceFill: Color {
        Color(.sRGB, red: 0.968, green: 0.969, blue: 0.974, opacity: 1)
    }

    private var previewSurfaceBorder: Color {
        Color.black.opacity(0.10)
    }

    private func previewWindow(style: PreviewWindowStyle, size: CGSize, compact: Bool) -> some View {
        let cornerRadius: CGFloat = compact ? 9 : 11
        let sidebarWidth = size.width * (compact ? 0.18 : 0.20)
        let bubbleWidth = compact ? 14.0 : 28.0
        let bubbleHeight = compact ? 5.0 : 8.0
        let circleSize = compact ? 2.6 : 4.2
        let circleSpacing = compact ? 2.8 : 4.2
        let topInset: CGFloat = compact ? 4 : 6
        let leadingInset: CGFloat = compact ? 5 : 7

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(windowShellFill(style: style))

            ZStack {
                wallpaper(style: style, size: size, compact: compact)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(sidebarGradient(style: style))
                        .frame(width: sidebarWidth)

                    Spacer(minLength: 0)
                }

                VStack {
                    HStack {
                        HStack(spacing: circleSpacing) {
                            Circle().fill(windowControl(.red, style: style))
                                .frame(width: circleSize, height: circleSize)
                            Circle().fill(windowControl(.yellow, style: style))
                                .frame(width: circleSize, height: circleSize)
                            Circle().fill(windowControl(.green, style: style))
                                .frame(width: circleSize, height: circleSize)
                        }

                        RoundedRectangle(cornerRadius: bubbleHeight / 2, style: .continuous)
                            .fill(bubbleFill(style: style))
                            .frame(width: bubbleWidth, height: bubbleHeight)
                            .padding(.leading, compact ? 4 : 6)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, topInset)
                    .padding(.leading, leadingInset)

                    Spacer(minLength: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 0.5, style: .continuous))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(windowOutline(style: style), lineWidth: compact ? 0.8 : 0.9)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: .black.opacity(style == .dark ? 0.16 : 0.10),
            radius: compact ? 4 : 6,
            y: compact ? 2 : 3
        )
    }

    private func windowShellFill(style: PreviewWindowStyle) -> Color {
        switch style {
        case .light:
            Color(.sRGB, red: 0.980, green: 0.985, blue: 0.993, opacity: 1)
        case .dark:
            Color(.sRGB, red: 0.110, green: 0.128, blue: 0.188, opacity: 1)
        }
    }

    private func wallpaper(style: PreviewWindowStyle, size: CGSize, compact: Bool) -> some View {
        ZStack {
            editorGradient(style: style)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: style == .dark
                            ? [
                                Color(.sRGB, red: 0.34, green: 0.24, blue: 0.82, opacity: 0.70),
                                Color(.sRGB, red: 0.05, green: 0.16, blue: 0.66, opacity: 0.12)
                            ]
                            : [
                                Color.white.opacity(0.88),
                                Color(.sRGB, red: 0.51, green: 0.74, blue: 0.96, opacity: 0.16)
                            ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(
                    width: size.width * (compact ? 0.92 : 1.04),
                    height: size.height * (compact ? 0.70 : 0.78)
                )
                .rotationEffect(.degrees(-24))
                .offset(
                    x: size.width * 0.16,
                    y: -size.height * 0.12
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: style == .dark
                            ? [
                                Color(.sRGB, red: 0.20, green: 0.70, blue: 0.96, opacity: 0.24),
                                Color.clear
                            ]
                            : [
                                Color.white.opacity(0.58),
                                Color.clear
                            ],
                        center: .center,
                        startRadius: 0,
                        endRadius: compact ? 14 : 20
                    )
                )
                .frame(
                    width: size.width * 0.34,
                    height: size.height * 0.56
                )
                .offset(
                    x: size.width * 0.30,
                    y: size.height * 0.18
                )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Rectangle()
                    .fill(bottomBarFill(style: style))
                    .frame(height: compact ? 9 : 11)
            }
        }
    }

    private func editorGradient(style: PreviewWindowStyle) -> LinearGradient {
        LinearGradient(
            colors: style == .dark
                ? [
                    Color(.sRGB, red: 0.17, green: 0.26, blue: 0.58, opacity: 1),
                    Color(.sRGB, red: 0.03, green: 0.09, blue: 0.44, opacity: 1)
                ]
                : [
                    Color(.sRGB, red: 0.89, green: 0.94, blue: 0.99, opacity: 1),
                    Color(.sRGB, red: 0.52, green: 0.73, blue: 0.95, opacity: 1)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func sidebarGradient(style: PreviewWindowStyle) -> LinearGradient {
        LinearGradient(
            colors: style == .dark
                ? [
                    Color(.sRGB, red: 0.18, green: 0.21, blue: 0.30, opacity: 0.95),
                    Color(.sRGB, red: 0.16, green: 0.19, blue: 0.27, opacity: 0.95)
                ]
                : [
                    Color(.sRGB, red: 0.72, green: 0.84, blue: 0.96, opacity: 0.92),
                    Color(.sRGB, red: 0.64, green: 0.80, blue: 0.95, opacity: 0.92)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func bottomBarFill(style: PreviewWindowStyle) -> Color {
        switch style {
        case .light:
            Color(.sRGB, red: 0.985, green: 0.988, blue: 0.995, opacity: 0.96)
        case .dark:
            Color(.sRGB, red: 0.05, green: 0.07, blue: 0.12, opacity: 0.96)
        }
    }

    private func bubbleFill(style: PreviewWindowStyle) -> Color {
        switch style {
        case .light:
            Color.white.opacity(0.58)
        case .dark:
            Color.white.opacity(0.12)
        }
    }

    private func windowOutline(style: PreviewWindowStyle) -> Color {
        style == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    private func windowControl(_ tint: Color, style: PreviewWindowStyle) -> Color {
        style == .dark ? tint.opacity(0.92) : tint.opacity(0.84)
    }
}

// MARK: - Section 4: History
