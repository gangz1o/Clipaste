import SwiftUI


extension GeneralSettingsView {
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

extension GeneralSettingsView {
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
