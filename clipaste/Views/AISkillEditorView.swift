import SwiftUI

struct AISkillEditorView: View {
    @Bindable var viewModel: AISettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.isEditingExistingSkill ? LocalizedStringKey("Edit AI Skill") : LocalizedStringKey("Add AI Skill"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            Form {
                Section {
                    TextField(LocalizedStringKey("Skill Name"), text: $viewModel.editingSkill.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.editingSkill.name) { _, _ in
                            if viewModel.skillEditorError != nil {
                                viewModel.skillEditorError = nil
                            }
                        }

                    Toggle(LocalizedStringKey("Enabled"), isOn: $viewModel.editingSkill.isEnabled)
                        .toggleStyle(.checkbox)
                } header: {
                    Text(LocalizedStringKey("Basic"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(AISkillContentTypeOption.allCases) { option in
                        Toggle(
                            option.title,
                            isOn: supportedContentBinding(for: option.contentType)
                        )
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    Text(LocalizedStringKey("Supported Content"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $viewModel.editingSkill.promptTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: 128)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )

                    HStack(spacing: 8) {
                        ForEach(AISkillPromptVariable.allCases) { variable in
                            Button {
                                insertPromptVariable(variable)
                            } label: {
                                Label {
                                    Text(verbatim: variable.token)
                                } icon: {
                                    Image(systemName: "plus")
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }

                    Text(LocalizedStringKey("AI Skill Prompt Template Hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(LocalizedStringKey("Prompt Template"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker(LocalizedStringKey("AI Configuration"), selection: $viewModel.editingSkill.configurationID) {
                        Text(LocalizedStringKey("Use Active Configuration")).tag(UUID?.none)
                        ForEach(viewModel.configurations) { config in
                            Text(config.displayTitle).tag(Optional(config.id))
                        }
                    }

                    Picker(LocalizedStringKey("Output Mode"), selection: $viewModel.editingSkill.outputMode) {
                        ForEach(AISkillOutputMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }

                    Toggle(LocalizedStringKey("Open Conversation After Running"), isOn: $viewModel.editingSkill.opensConversation)
                        .toggleStyle(.checkbox)
                } header: {
                    Text(LocalizedStringKey("Run Behavior"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let error = viewModel.skillEditorError {
                    Label {
                        Text(verbatim: error)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(2)
                }

                Spacer()

                Button(LocalizedStringKey("Cancel"), role: .cancel) {
                    viewModel.skillEditorError = nil
                    viewModel.isSkillEditorPresented = false
                }

                Button(LocalizedStringKey("Save")) {
                    viewModel.saveEditingSkill()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 620)
    }

    private var isSaveDisabled: Bool {
        viewModel.editingSkill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        viewModel.editingSkill.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        viewModel.editingSkill.supportedContentTypes.isEmpty
    }

    private func supportedContentBinding(for contentType: ClipboardContentType) -> Binding<Bool> {
        Binding {
            viewModel.editingSkill.supportedContentTypes.contains(contentType)
        } set: { isSelected in
            if isSelected {
                viewModel.editingSkill.supportedContentTypes.insert(contentType)
            } else {
                viewModel.editingSkill.supportedContentTypes.remove(contentType)
            }
        }
    }

    private func insertPromptVariable(_ variable: AISkillPromptVariable) {
        let token = variable.templateToken

        if viewModel.editingSkill.promptTemplate.isEmpty ||
            viewModel.editingSkill.promptTemplate.last?.isWhitespace == true {
            viewModel.editingSkill.promptTemplate += token
        } else {
            viewModel.editingSkill.promptTemplate += " \(token)"
        }
    }
}

private enum AISkillPromptVariable: String, CaseIterable, Identifiable {
    case text = "clipboard.text"
    case title = "clipboard.title"
    case type = "clipboard.type"

    var id: String { rawValue }

    var token: String { rawValue }

    var templateToken: String {
        "{{\(rawValue)}}"
    }
}

private enum AISkillContentTypeOption: CaseIterable, Identifiable {
    case text
    case code
    case link
    case image
    case fileURL

    var id: ClipboardContentType { contentType }

    var contentType: ClipboardContentType {
        switch self {
        case .text: return .text
        case .code: return .code
        case .link: return .link
        case .image: return .image
        case .fileURL: return .fileURL
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .text: return "Text Content"
        case .code: return "Code Content"
        case .link: return "Link Content"
        case .image: return "Image Content"
        case .fileURL: return "File Content"
        }
    }
}

private extension AISkillOutputMode {
    var title: LocalizedStringKey {
        switch self {
        case .copyToClipboard: return "Copy Result to Clipboard"
        case .createClipboardItem: return "Create Clipboard Item"
        case .replaceCurrentItem: return "Replace Current Item"
        case .pasteToActiveApp: return "Paste Result to Active App"
        case .openConversation: return "Open AI Conversation"
        }
    }
}
