import SwiftUI
import UniformTypeIdentifiers


struct GroupOverflowSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GroupOverflowRow: View {
    enum Title {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: Title
    let icon: String?
    let isSelected: Bool
    let accentColor: AppAccentColor
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = ClipboardGroupIconName.normalize(icon) {
                    GroupIconView(iconName: iconName, size: 13)
                        .frame(width: 14, height: 14)
                } else {
                    Spacer()
                        .frame(width: 14, height: 14)
                }

                titleView
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isHighlighted ? accentColor.selectedContentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? accentColor.color : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch title {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let string):
            Text(verbatim: string)
        }
    }
}

struct AIModelOverflowRow: View {
    let configuration: AIConfiguration
    let isSelected: Bool
    let accentColor: AppAccentColor
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AIProviderIconView(configuration: configuration, size: 14)
                    .frame(width: 14, height: 14)

                Text(verbatim: configuration.displayTitle)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isHighlighted ? accentColor.selectedContentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? accentColor.color : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ClipboardHeaderPreview: View {
    @FocusState private var focusedField: ClipboardPanelFocusField?

    var body: some View {
        ClipboardHeaderView(
            viewModel: ClipboardViewModel(clipboardMonitor: nil),
            focusedField: _focusedField
        )
        .environmentObject(AppPreferencesStore.shared)
        .frame(width: 380)
    }
}

// MARK: - 极简原生 Tab 按钮子组件
