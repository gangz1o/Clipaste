import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    @State private var showingClearAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch Clipaste at Login", isOn: $viewModel.launchAtLogin)
                    .toggleStyle(.switch)

                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                Picker("Language", selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text("Launch & Language")
            } footer: {
                Text("Language changes take full effect after the next launch.")
            }

            Section {
                Toggle("Use Vertical List Layout", isOn: $viewModel.isVerticalLayout)
                    .toggleStyle(.switch)

                if viewModel.isVerticalLayout {
                    Picker("Display Position", selection: $viewModel.verticalFollowMode) {
                        ForEach(VerticalFollowMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            } header: {
                Text("Window")
            } footer: {
                Text("Horizontal cards are better for browsing; vertical list is better for quick switching and searching.")
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isVerticalLayout)

            Section {
                Picker("Retention Period", selection: $viewModel.historyRetention) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
            } header: {
                Text("History")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()

                        Button(role: .destructive) {
                            showingClearAlert = true
                        } label: {
                            Label("Clear History…", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("Permanently deletes all clipboard records and image caches. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .alert("Clear All History?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    StorageManager.shared.clearAllHistory()
                }
            } message: {
                Text("Permanently deletes all clipboard records and image caches. This cannot be undone.")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsViewModel())
}
