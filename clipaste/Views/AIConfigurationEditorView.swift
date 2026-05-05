import SwiftUI

/// Sheet for adding or editing a single AIConfiguration.
struct AIConfigurationEditorView: View {
    @Bindable var viewModel: AISettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.isEditingExisting ? LocalizedStringKey("Edit AI Configuration") : LocalizedStringKey("Add AI Configuration"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Form
            Form {
                // Name
                Section {
                    TextField(LocalizedStringKey("Configuration Name"), text: $viewModel.editingConfiguration.name)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text(LocalizedStringKey("Name"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Provider
                Section {
                    Picker(LocalizedStringKey("Provider"), selection: $viewModel.editingConfiguration.providerType) {
                        ForEach(AIProviderType.allCases) { type in
                            Text(LocalizedStringKey(type.rawValue)).tag(type)
                        }
                    }
                    .onChange(of: viewModel.editingConfiguration.providerType) { _, newType in
                        let newModel = newType.defaultModels.first ?? ""
                        viewModel.editingConfiguration.endpoint = newType.defaultEndpoint
                        viewModel.editingConfiguration.model = newModel
                        viewModel.editingConfiguration.supportsImage = AIConfiguration.defaultSupportsImage(provider: newType, model: newModel)
                        viewModel.testResult = nil
                    }
                } header: {
                    Text(LocalizedStringKey("Provider Selection"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Credentials
                Section {
                    SecureField(LocalizedStringKey("API Key"), text: $viewModel.editingConfiguration.apiKey)
                        .textFieldStyle(.roundedBorder)

                    if viewModel.editingConfiguration.providerType == .custom {
                        TextField(LocalizedStringKey("API Endpoint"), text: $viewModel.editingConfiguration.endpoint)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(LocalizedStringKey("API Endpoint"), text: $viewModel.editingConfiguration.endpoint)
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(.secondary)
                            .disabled(true)
                    }

                    if viewModel.editingConfiguration.providerType == .custom {
                        TextField(LocalizedStringKey("Model ID"), text: $viewModel.editingConfiguration.model)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker(LocalizedStringKey("Model"), selection: $viewModel.editingConfiguration.model) {
                            ForEach(viewModel.editingConfiguration.providerType.defaultModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: viewModel.editingConfiguration.model) { _, newModel in
                            viewModel.editingConfiguration.supportsImage = AIConfiguration.defaultSupportsImage(
                                provider: viewModel.editingConfiguration.providerType,
                                model: newModel
                            )
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("Configuration"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(LocalizedStringKey("Model Supports Image Input"), isOn: $viewModel.editingConfiguration.supportsImage)
                } header: {
                    Text(LocalizedStringKey("Capabilities"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text(LocalizedStringKey("Model Supports Image Input Footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer Buttons
            HStack {
                // Test connection + result
                if let result = viewModel.testResult {
                    switch result {
                    case .success(let msg):
                        Label(LocalizedStringKey(msg), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .failure(let errorMsg):
                        Label(LocalizedStringKey(errorMsg), systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(LocalizedStringKey("Test Connection")) {
                    Task { await viewModel.testConnection() }
                }
                .disabled(viewModel.isTesting || viewModel.editingConfiguration.apiKey.isEmpty)
                .overlay {
                    if viewModel.isTesting {
                        ProgressView().controlSize(.small)
                    }
                }

                Button(LocalizedStringKey("Cancel"), role: .cancel) {
                    viewModel.isEditorPresented = false
                    viewModel.testResult = nil
                }

                Button(LocalizedStringKey("Save")) {
                    viewModel.saveEditing()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.editingConfiguration.apiKey.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 440)
    }
}
