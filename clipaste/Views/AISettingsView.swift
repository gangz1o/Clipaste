import SwiftUI

struct AISettingsView: View {
    @State private var viewModel = AISettingsViewModel.shared
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        Form {
            enableAISection
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

    // MARK: - Enable AI Section

    private var enableAISection: some View {
        Section {
            AISettingsToggleRow(
                title: LocalizedStringKey("Enable AI"),
                isOn: Binding(
                    get: { viewModel.isAIEnabled },
                    set: { viewModel.isAIEnabled = $0 }
                )
            )
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
            AISettingsToggleRow(
                title: LocalizedStringKey("Use AI for Image OCR"),
                message: viewModel.canEnableAIOCR ? nil : LocalizedStringKey("AI OCR Requires Configuration"),
                isOn: Binding(
                    get: { viewModel.isAIOCREnabled },
                    set: { viewModel.isAIOCREnabled = $0 }
                )
            )
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
