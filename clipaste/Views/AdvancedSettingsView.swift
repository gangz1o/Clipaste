import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @Environment(ClipboardRuntimeStore.self) private var runtimeStore
    @Environment(\.locale) private var locale
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("enable_smart_groups") private var isSmartGroupsEnabled: Bool = true

    var body: some View {
        Form {
            coreInteractionSection
            interfaceSection
            migrationSection
            dataSyncSection
        }
        .settingsPageChrome()
    }
}

// MARK: - Section 1: Interaction & Behavior

private extension AdvancedSettingsView {
    var coreInteractionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $viewModel.autoPasteToActiveApp) {
                    Text("Auto-Paste to Active App on Double-Click")
                }
                if viewModel.autoPasteToActiveApp {
                    Button("Open Accessibility Settings…", action: viewModel.openAccessibilitySettings)
                        .buttonStyle(.plain)
                        .tint(appAccentColor.color)
                        .font(.subheadline)
                        .foregroundStyle(appAccentColor.color)
                        .padding(.leading, 2)
                }
            }

            Toggle(isOn: $viewModel.moveToTopAfterPaste) {
                Text("Move Item to Top After Pasting")
            }

            Toggle(isOn: $viewModel.clearSearchOnPanelActivation) {
                Text("Clear Search When Opening Clipboard History")
            }

            Toggle(isOn: $viewModel.autoFocusFirstItemOnPanelActivation) {
                Text("Auto-Focus First Item When Opening Clipboard History")
            }

            Toggle(isOn: $viewModel.requireCmdToDelete) {
                Text("Require Cmd+Backspace to Delete")
            }

            Picker("Default Text Format", selection: $viewModel.pasteTextFormat) {
                ForEach(PasteTextFormat.allCases) { format in
                    Text(format.localizedTitle).tag(format)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Interaction & Behavior")
        }
    }
}

// MARK: - Section 2: Interface

private extension AdvancedSettingsView {
    var interfaceSection: some View {
        Section {
            Toggle(isOn: $isSmartGroupsEnabled) {
                Text("Show Smart Groups")
            }

            Picker("Link Display Mode", selection: $viewModel.linkDisplayMode) {
                ForEach(ClipboardLinkDisplayMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Interface")
        }
    }
}

// MARK: - Section 3: Migration Assistant

private extension AdvancedSettingsView {
    var migrationSection: some View {
        Section {
            MigrationView()
        } header: {
            SettingsSectionHeader(title: "Migration Assistant")
        }
    }
}

// MARK: - Section 4: Data Sync

private extension AdvancedSettingsView {
    var dataSyncSection: some View {
        Section {
            Toggle(isOn: syncEnabledBinding) {
                Text("iCloud Sync")
            }
            .disabled(runtimeStore.isSyncing)

            if runtimeStore.isSyncEnabled {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 8, height: 8)
                            .opacity(runtimeStore.isSyncing ? 0.5 : 1.0)
                            .animation(
                                runtimeStore.isSyncing
                                    ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                    : .default,
                                value: runtimeStore.isSyncing
                            )

                        syncStatusText
                    }

                    Spacer()

                    Button("Check iCloud Connection Status", systemImage: "arrow.triangle.2.circlepath") {
                        runtimeStore.refreshCurrentRoute()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .bold()
                    .rotationEffect(Angle(degrees: runtimeStore.isSyncing ? 360 : 0))
                    .animation(
                        runtimeStore.isSyncing
                            ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: runtimeStore.isSyncing
                    )
                    .foregroundStyle(runtimeStore.isSyncing ? .secondary : appAccentColor.color)
                    .disabled(runtimeStore.isSyncing)
                }

            }
        } header: {
            SettingsSectionHeader(title: "Data Sync")
        }
    }
}

// MARK: - Helpers

private extension AdvancedSettingsView {
    var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { runtimeStore.isSyncEnabled },
            set: { runtimeStore.setSyncEnabled($0) }
        )
    }

    var syncStatusColor: Color {
        if runtimeStore.isSyncing { return appAccentColor.color }
        if runtimeStore.syncError != nil { return .red }
        return .green
    }

    @ViewBuilder
    var syncStatusText: some View {
        if runtimeStore.isSyncing {
            Text(xcstringsLocalized("Syncing…", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let error = runtimeStore.syncError {
            let template = xcstringsLocalized("Sync Failed: %@", locale: locale)
            Text(String(format: template, locale: locale, arguments: [error]))
                .font(.subheadline)
                .foregroundStyle(.red)
        } else if let date = runtimeStore.lastSyncDate {
            let formatted = date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
            )
            let template = xcstringsLocalized("Last Sync: %@", locale: locale)
            Text(String(format: template, locale: locale, arguments: [formatted]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(xcstringsLocalized("Waiting for First Sync…", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func xcstringsLocalized(_ key: String, locale: Locale) -> String {
        let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
        return String(localized: resource)
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environment(ClipboardRuntimeStore.shared)
}
