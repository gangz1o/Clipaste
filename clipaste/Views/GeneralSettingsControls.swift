import SwiftUI


struct PreviewPanelToggle: View {
    @AppStorage("previewPanelMode") private var previewPanelMode: PreviewPanelMode = .disabled

    var body: some View {
        Toggle(isOn: Binding(
            get: { previewPanelMode == .enabled },
            set: { previewPanelMode = $0 ? .enabled : .disabled }
        )) {
            Text("Preview Panel")
        }
    }
}

struct AppearanceThemePicker: View {
    @Binding var selection: AppTheme
    let accentColor: Color

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    AppearanceThemeCard(
                        theme: theme,
                        isSelected: selection == theme,
                        accentColor: accentColor
                    ) {
                        selection = theme
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text("Appearance")
        }
    }
}

struct AppearanceThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearanceThemePreview(
                    theme: theme,
                    isSelected: isSelected,
                    accentColor: accentColor
                )

                Text(theme.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
