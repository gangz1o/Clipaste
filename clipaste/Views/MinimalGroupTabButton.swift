import SwiftUI
import UniformTypeIdentifiers


struct MinimalGroupTabButton: View {
    private enum Metrics {
        static let iconSize: CGFloat = 14
    }

    enum Title {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: Title
    let icon: String?
    let isSelected: Bool
    var maxTextWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 5
    var iconSpacing: CGFloat = 5
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue

    var body: some View {
        Button(action: action) {
            HStack(spacing: resolvedIconName == nil ? 0 : iconSpacing) {
                if let resolvedIconName {
                    GroupIconView(iconName: resolvedIconName, size: Metrics.iconSize)
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                }
                Group {
                    switch title {
                    case .localized(let resource):
                        Text(resource)
                    case .verbatim(let string):
                        Text(verbatim: string)
                    }
                }
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .if(maxTextWidth != nil) { view in
                        view.frame(maxWidth: maxTextWidth!, alignment: .leading)
                    }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tabBackground)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(appAccentColor.selectedContentColor)
        }
        return AnyShapeStyle(isHovered ? Color.primary : Color.secondary)
    }

    private var resolvedIconName: String? {
        ClipboardGroupIconName.normalize(icon)
    }

    private var tabBackground: some View {
        Capsule(style: .continuous)
            .fill(backgroundFillStyle)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderStyle, lineWidth: borderLineWidth)
            }
    }

    private var backgroundFillStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(appAccentColor.color)
        }

        if isHovered {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.045)
            )
        }

        return AnyShapeStyle(Color.clear)
    }

    private var borderStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(appAccentColor.color.opacity(colorScheme == .dark ? 0.82 : 0.64))
        }

        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 1 : (isHovered ? 0.6 : 0)
    }
}

// MARK: - Conditional View Modifier
