import SwiftUI

struct AISettingsView: View {
    @State private var viewModel = AISettingsViewModel()
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        Form {
            configurationsSection
        }
        .settingsPageChrome()
        .id("ai-settings-\(appLanguage.rawValue)")
        .environment(\.locale, appLanguage.resolvedLocale)
        .sheet(isPresented: $viewModel.isEditorPresented) {
            AIConfigurationEditorView(viewModel: viewModel)
                .id("ai-settings-editor-\(appLanguage.rawValue)")
                .environment(\.locale, appLanguage.resolvedLocale)
        }
    }

    // MARK: - Configurations List Section

    private var configurationsSection: some View {
        Section {
            if viewModel.configurations.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.configurations) { config in
                    AIConfigurationRow(
                        config: config,
                        isActive: viewModel.activeConfigurationID == config.id,
                        onSetActive: { viewModel.setActive(config) },
                        onEdit: { viewModel.edit(config) },
                        onDelete: { viewModel.delete(config) }
                    )
                }
            }
        } header: {
            HStack {
                SettingsSectionHeader(title: LocalizedStringKey("AI Configurations"))
                Spacer()
                Button {
                    viewModel.addNew()
                } label: {
                    Label(LocalizedStringKey("Add Configuration"), systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(LocalizedStringKey("Add Configuration"))
            }
        } footer: {
            SettingsSectionFooter {
                Text(LocalizedStringKey("AI Configurations Footer"))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(LocalizedStringKey("No AI Configurations"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(LocalizedStringKey("Add Your First Configuration")) {
                viewModel.addNew()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Configuration Row

private struct AIConfigurationRow: View {
    let config: AIConfiguration
    let isActive: Bool
    let onSetActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Button(action: onSetActive) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? appAccentColor.color : Color.secondary)
                    .font(.system(size: 16))
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("Set as Active"))

            // Provider icon + info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.displayTitle)
                        .fontWeight(.medium)
                    if isActive {
                        Text(LocalizedStringKey("Active"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appAccentColor.color.opacity(0.15))
                            .foregroundStyle(appAccentColor.color)
                            .clipShape(Capsule())
                    }
                }
                Text("\(config.providerType.rawValue) · \(config.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appAccentColor.color)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Edit Configuration"))

            // Delete button
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Delete Configuration"))
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            LocalizedStringKey("Delete AI Configuration Confirmation Title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("Delete Configuration"), role: .destructive, action: onDelete)
            Button(LocalizedStringKey("Cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Delete AI Configuration Confirmation Message"))
        }
    }
}

#Preview {
    AISettingsView()
}
