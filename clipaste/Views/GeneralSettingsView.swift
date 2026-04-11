import SwiftUI

// MARK: - Settings Card Container

private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .settingsSectionTitle()
            
            content
                .liquidGlassCard()
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Setting Row

private struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing
        }
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    @State private var showingClearAlert = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                launchAndLanguageCard
                windowCard
                feedbackCard
                historyCard
            }
            .padding(20)
        }
        .settingsScrollChromeHidden()
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 440, alignment: .top)
        .onAppear {
            preferencesStore.refreshLaunchAtLoginStatus()
        }
    }
}

// MARK: - Card 1: Launch & Language

private extension GeneralSettingsView {
    var launchAndLanguageCard: some View {
        SettingsCard(title: "Startup & Language", systemImage: "globe") {
            VStack(spacing: 0) {
                SettingRow(
                    icon: "power",
                    title: "Launch Clipaste at Login"
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                cardDivider

                SettingRow(
                    icon: "paintbrush",
                    title: "Appearance"
                ) {
                    Picker("", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                cardDivider

                SettingRow(
                    icon: "character.bubble",
                    title: "Language"
                ) {
                    Picker("", selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.localizedDisplayName)
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Card 2: Window

private extension GeneralSettingsView {
    var windowCard: some View {
        SettingsCard(title: "Window", systemImage: "macwindow") {
            VStack(spacing: 0) {
                SettingRow(
                    icon: "rectangle.split.2x1",
                    title: "Use Vertical List Layout",
                    subtitle: "Horizontal cards are better for browsing; vertical list is better for quick switching and searching."
                ) {
                    Toggle("", isOn: $viewModel.isVerticalLayout)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if viewModel.isVerticalLayout {
                    cardDivider

                    SettingRow(
                        icon: "arrow.up.and.down",
                        title: "Display Position"
                    ) {
                        Picker("", selection: $viewModel.verticalFollowMode) {
                            ForEach(VerticalFollowMode.allCases) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isVerticalLayout)
        }
    }
}

// MARK: - Card 3: Feedback & Sound

private extension GeneralSettingsView {
    var feedbackCard: some View {
        SettingsCard(title: "Feedback & Sound", systemImage: "speaker.wave.2") {
            SettingRow(
                icon: "speaker.badge.exclamationmark",
                title: "Copy Notification Sound",
                subtitle: "Play a short sound after copying to the clipboard."
            ) {
                Toggle("", isOn: $viewModel.isCopySoundEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Card 4: History

private extension GeneralSettingsView {
    var historyCard: some View {
        SettingsCard(title: "History", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                SettingRow(
                    icon: "calendar",
                    title: "Retention Period"
                ) {
                    Picker("", selection: $viewModel.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.localizedTitle).tag(retention)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                cardDivider

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

                Text("Permanently deletes non-favorite clipboard records and image caches. Items in Favorites are kept.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
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

// MARK: - Shared UI

private extension GeneralSettingsView {
    var cardDivider: some View {
        Divider()
            .padding(.vertical, 10)
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
