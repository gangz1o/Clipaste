import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal

    @State private var showingClearAlert = false

    var body: some View {
        Form {
            startupLanguageSection
            windowSection
            feedbackSection
            historySection
        }
        .settingsPageChrome()
        .onAppear {
            preferencesStore.refreshLaunchAtLoginStatus()
        }
    }
}

// MARK: - Section 1: Startup & Language

private extension GeneralSettingsView {
    var startupLanguageSection: some View {
        Section {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch Clipaste at Login")
            }

            Picker("Appearance", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }

            Picker("Language", selection: $viewModel.appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.localizedDisplayName).tag(lang)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Startup & Language")
        }
    }
}

// MARK: - Section 2: Window

private extension GeneralSettingsView {
    var windowSection: some View {
        Section {
            Picker("Layout Mode", selection: $clipboardLayout) {
                ForEach(AppLayoutMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }

            PreviewPanelToggle()
        } header: {
            SettingsSectionHeader(title: "Window")
        } footer: {
            SettingsSectionFooter {
                Text("Layout Mode controls how clipboard items are displayed. Preview Panel shows detailed preview when using vertical layouts.")
            }
        }
    }
}

private struct PreviewPanelToggle: View {
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

// MARK: - Section 3: Feedback & Sound

private extension GeneralSettingsView {
    var feedbackSection: some View {
        Section {
            Toggle(isOn: $viewModel.isCopySoundEnabled) {
                Text("Copy Notification Sound")
            }
        } header: {
            SettingsSectionHeader(title: "Feedback & Sound")
        } footer: {
            SettingsSectionFooter {
                Text("Play a short sound after copying to the clipboard.")
            }
        }
    }
}

// MARK: - Section 4: History

private extension GeneralSettingsView {
    var historySection: some View {
        Section {
            Picker("Retention Period", selection: $viewModel.historyRetention) {
                ForEach(HistoryRetention.allCases) { retention in
                    Text(retention.localizedTitle).tag(retention)
                }
            }

            LabeledContent {
                Button(role: .destructive) {
                    showingClearAlert = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            } label: {
                Text("Clear History")
            }
        } header: {
            SettingsSectionHeader(title: "History")
        } footer: {
            SettingsSectionFooter {
                Text("Permanently deletes non-favorite clipboard records and image caches. Items in Favorites are kept.")
            }
        }
        .alert("Clear History?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) {
                StorageManager.shared.clearUnpinnedHistory()
            }
        } message: {
            Text("Permanently deletes non-favorite clipboard records and image caches. Items in Favorites are kept.")
        }
    }
}

// MARK: - Helpers

private extension GeneralSettingsView {
    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferencesStore.launchAtLogin },
            set: { preferencesStore.updateLaunchAtLogin($0) }
        )
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AppPreferencesStore.shared)
}
