import AppKit
import SwiftUI

// MARK: - Settings Card Container

private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .settingsSectionTitle()

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }
}

// MARK: - Setting Row

private struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            trailing
        }
    }
}

// MARK: - Advanced Settings View

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @Environment(\.locale) private var locale
    @AppStorage("enable_smart_groups") private var isSmartGroupsEnabled: Bool = true
    @State private var showsDiagnostics = false
    @State private var copiedDiagnostics = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                coreInteractionCard
                interfaceCard
                migrationCard
                dataSyncCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .settingsScrollChromeHidden()
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 440, alignment: .top)
    }
}

// MARK: - Card 1: Core Interaction & Behavior

private extension AdvancedSettingsView {
    var coreInteractionCard: some View {
        SettingsCard(title: "Interaction & Behavior", systemImage: "hand.tap") {
            VStack(spacing: 0) {
                // Paste Setting
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow(
                        icon: "doc.on.clipboard",
                        title: "Auto-Paste to Active App on Double-Click",
                        subtitle: "When disabled, double-clicking an item only copies it to the clipboard without sending the paste shortcut."
                    ) {
                        Toggle("", isOn: $viewModel.autoPasteToActiveApp)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    if viewModel.autoPasteToActiveApp {
                        Button("Open Accessibility Settings…", action: viewModel.openAccessibilitySettings)
                            .buttonStyle(.link)
                            .font(.subheadline)
                            .padding(.leading, 32)
                    }
                }

                cardDivider

                // Sort Setting
                SettingRow(
                    icon: "arrow.up.to.line",
                    title: "Move Item to Top After Pasting",
                    subtitle: "Useful when you repeatedly paste the same content."
                ) {
                    Toggle("", isOn: $viewModel.moveToTopAfterPaste)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                cardDivider

                SettingRow(
                    icon: "magnifyingglass",
                    title: "Clear Search When Opening Clipboard History",
                    subtitle: "Always reset the search field each time the clipboard history panel opens."
                ) {
                    Toggle("", isOn: $viewModel.clearSearchOnPanelActivation)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                cardDivider

                SettingRow(
                    icon: "delete.backward",
                    title: "Require Cmd+Backspace to Delete",
                    subtitle: "When enabled, items can only be deleted using Cmd+Backspace instead of just Backspace."
                ) {
                    Toggle("", isOn: $viewModel.requireCmdToDelete)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                cardDivider

                // Text Format Setting
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "textformat")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(xcstringsLocalized("Default Text Format", locale: locale))
                            .font(.body)
                        Text(holdPlainTextOutputHint(locale: locale))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Picker("", selection: $viewModel.pasteTextFormat) {
                        ForEach(PasteTextFormat.allCases) { format in
                            Text(format.localizedTitle).tag(format)
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

// MARK: - Card 2: Interface

private extension AdvancedSettingsView {
    var interfaceCard: some View {
        SettingsCard(title: "Interface", systemImage: "macwindow") {
            SettingRow(
                icon: "rectangle.3.group",
                title: "Show Smart Groups",
                subtitle: "Display preset category tabs like Text, Links, and Images in the navigation bar."
            ) {
                Toggle("", isOn: $isSmartGroupsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Card 3: Migration Assistant

private extension AdvancedSettingsView {
    var migrationCard: some View {
        SettingsCard(title: "Migration Assistant", systemImage: "shippingbox") {
            MigrationView()
        }
    }
}

// MARK: - Card 4: Data Sync

private extension AdvancedSettingsView {
    var dataSyncCard: some View {
        SettingsCard(title: "Data Sync", systemImage: "icloud") {
            VStack(alignment: .leading, spacing: 12) {
                // iCloud Sync Toggle
                Toggle(isOn: syncEnabledBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync via iCloud")
                            .font(.body)
                        Text("Seamlessly sync clipboard history across all Macs signed in with the same Apple ID.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(runtimeStore.isSyncing)

                // Sync Console
                if runtimeStore.isSyncEnabled {
                    Divider()

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
                        .foregroundStyle(runtimeStore.isSyncing ? .secondary : Color.accentColor)
                        .disabled(runtimeStore.isSyncing)
                    }
                }

                diagnosticsPanel
            }
        }
    }
}

// MARK: - Shared UI Components

private extension AdvancedSettingsView {
    var cardDivider: some View {
        Divider()
            .padding(.vertical, 10)
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
        if runtimeStore.isSyncing { return .blue }
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

    var diagnosticsPanel: some View {
        DisclosureGroup(isExpanded: $showsDiagnostics) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Active Route")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.activeRoute == "cloud" ? String(localized: "iCloud") : String(localized: "Local"))
                }

                HStack {
                    Text("Current Toggle State")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.currentSyncEnabled ? String(localized: "On") : String(localized: "Off"))
                }

                HStack {
                    Text("Pending Toggle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pendingSyncDescription)
                }

                HStack {
                    Text("Local Runtime")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.localRuntimeReady ? String(localized: "Initialized") : String(localized: "Not Initialized"))
                }

                HStack {
                    Text("Cloud Runtime")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.cloudRuntimeReady ? String(localized: "Initialized") : String(localized: "Not Initialized"))
                }

                HStack {
                    Text("Runtime Generation")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.runtimeGeneration)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Store")
                        .foregroundStyle(.secondary)
                    Text(runtimeStore.diagnosticsSnapshot.localStorePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud Store")
                        .foregroundStyle(.secondary)
                    Text(runtimeStore.diagnosticsSnapshot.cloudStorePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if let error = runtimeStore.diagnosticsSnapshot.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Error")
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent Events")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(copiedDiagnostics ? String(localized: "Copied") : String(localized: "Copy Diagnostics")) {
                            copyDiagnosticsToPasteboard()
                        }
                        .buttonStyle(.borderless)
                        .disabled(runtimeStore.diagnosticsEntries.isEmpty)
                    }

                    if runtimeStore.diagnosticsEntries.isEmpty {
                        Text("No Events Recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runtimeStore.diagnosticsEntries.prefix(8)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)

                                Text(entry.level.rawValue)
                                    .font(.caption2.monospaced())
                                    .bold()
                                    .foregroundStyle(color(for: entry.level))

                                Text(entry.message)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Sync Diagnostics", systemImage: "stethoscope")
                .font(.subheadline)
        }
        .padding(.top, 2)
    }

    var pendingSyncDescription: String {
        guard let pending = runtimeStore.diagnosticsSnapshot.pendingSyncEnabled else {
            return String(localized: "None")
        }

        return pending ? String(localized: "Pending Enable") : String(localized: "Pending Disable")
    }

    func color(for level: ClipboardSyncDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    func copyDiagnosticsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(runtimeStore.diagnosticsReport(), forType: .string)
        copiedDiagnostics = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedDiagnostics = false
        }
    }

    /// `String(localized:locale:)` 对含 `%@` 的部分键在运行时可能仍回退到开发语言；从对应 `.lproj` 取串更可靠。
    private func xcstringsLocalized(_ key: String, locale: Locale) -> String {
        let bcp47 = locale.identifier(.bcp47)
        if let path = Bundle.main.path(forResource: bcp47, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        return String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }

    private func holdPlainTextOutputHint(locale: Locale) -> String {
        let key = "Hold %@ while copying or pasting to force plain text output."
        let template = xcstringsLocalized(key, locale: locale)
        let arg = viewModel.plainTextModifier.pickerLabel(locale: locale)
        return String(format: template, locale: locale, arguments: [arg])
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(ClipboardRuntimeStore.shared)
}
