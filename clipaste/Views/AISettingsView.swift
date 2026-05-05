import SwiftUI

struct AISettingsView: View {
    @State private var viewModel = AISettingsViewModel.shared
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        Form {
            configurationsSection
            imageOCRSection
            skillsSection
        }
        .settingsPageChrome()
        .id("ai-settings-\(appLanguage.rawValue)")
        .environment(\.locale, appLanguage.resolvedLocale)
        .sheet(isPresented: $viewModel.isEditorPresented) {
            AIConfigurationEditorView(viewModel: viewModel)
                .id("ai-settings-editor-\(appLanguage.rawValue)")
                .environment(\.locale, appLanguage.resolvedLocale)
        }
        .sheet(isPresented: $viewModel.isSkillEditorPresented) {
            AISkillEditorView(viewModel: viewModel)
                .id("ai-skill-editor-\(appLanguage.rawValue)")
                .environment(\.locale, appLanguage.resolvedLocale)
        }
    }

    // MARK: - Skills List Section

    private var skillsSection: some View {
        Section {
            if viewModel.skills.isEmpty {
                emptySkillsState
            } else {
                ForEach(viewModel.skills) { skill in
                    AISkillRow(
                        skill: skill,
                        configurationTitle: configurationTitle(for: skill),
                        onToggle: { isEnabled in viewModel.setSkillEnabled(skill, isEnabled: isEnabled) },
                        onEdit: { viewModel.edit(skill) },
                        onDelete: { viewModel.delete(skill) }
                    )
                }
                .onMove(perform: viewModel.moveSkills)
            }
        } header: {
            HStack {
                SettingsSectionHeader(title: LocalizedStringKey("AI Skills"))
                Spacer()
                Button {
                    viewModel.addDefaultSkillsIfMissing()
                } label: {
                    Label(LocalizedStringKey("Add Preset Skills"), systemImage: "wand.and.sparkles")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(LocalizedStringKey("Add Preset Skills"))

                Button {
                    viewModel.addNewSkill()
                } label: {
                    Label(LocalizedStringKey("Add Skill"), systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(LocalizedStringKey("Add Skill"))
            }
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

    // MARK: - Image OCR Section

    private var imageOCRSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.isAIOCREnabled },
                set: { viewModel.isAIOCREnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("Use AI for Image OCR"))
                    if viewModel.canEnableAIOCR == false {
                        Text(LocalizedStringKey("AI OCR Requires Configuration"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(viewModel.canEnableAIOCR == false)
        } header: {
            SettingsSectionHeader(title: LocalizedStringKey("Image OCR"))
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

    private var emptySkillsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(LocalizedStringKey("No AI Skills"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(LocalizedStringKey("Add Your First Skill")) {
                viewModel.addNewSkill()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func configurationTitle(for skill: AISkill) -> String {
        guard let configurationID = skill.configurationID else {
            return String(localized: "Use Active Configuration")
        }

        return viewModel.configurations.first { $0.id == configurationID }?.displayTitle
            ?? String(localized: "Missing AI Configuration")
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

// MARK: - Skill Row

private struct AISkillRow: View {
    let skill: AISkill
    let configurationTitle: String
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(!skill.isEnabled)
            } label: {
                Image(systemName: skill.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(skill.isEnabled ? appAccentColor.color : Color.secondary)
                    .font(.system(size: 16))
                    .animation(.easeInOut(duration: 0.15), value: skill.isEnabled)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("Enable Skill"))

            Image(systemName: skill.outputMode.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(skill.isEnabled ? appAccentColor.color : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(skill.isEnabled ? .primary : .secondary)

                Text("\(contentSummary) · \(configurationTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appAccentColor.color)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Edit Skill"))

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Delete Skill"))
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            LocalizedStringKey("Delete AI Skill Confirmation Title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("Delete Skill"), role: .destructive, action: onDelete)
            Button(LocalizedStringKey("Cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Delete AI Skill Confirmation Message"))
        }
    }

    private var contentSummary: String {
        let orderedTypes: [ClipboardContentType] = [.text, .code, .link, .image, .fileURL, .color]
        let titles = orderedTypes
            .filter { skill.supportedContentTypes.contains($0) }
            .map { contentTypeTitle($0) }

        return titles.isEmpty ? String(localized: "No Supported Content") : titles.joined(separator: ", ")
    }

    private func contentTypeTitle(_ contentType: ClipboardContentType) -> String {
        switch contentType {
        case .text: return String(localized: "Text Content")
        case .code: return String(localized: "Code Content")
        case .link: return String(localized: "Link Content")
        case .image: return String(localized: "Image Content")
        case .fileURL: return String(localized: "File Content")
        case .color: return String(localized: "Color Content")
        }
    }
}

#Preview {
    AISettingsView()
}
