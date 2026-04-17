import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @Environment(\.locale) private var locale
    @AppStorage("enable_smart_groups") private var isSmartGroupsEnabled: Bool = true
    @State private var showsDiagnostics = false
    @State private var copiedDiagnostics = false

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
                        .buttonStyle(.link)
                        .font(.subheadline)
                        .padding(.leading, 2)
                }
            }

            Toggle(isOn: $viewModel.moveToTopAfterPaste) {
                Text("Move Item to Top After Pasting")
            }

            Toggle(isOn: $viewModel.clearSearchOnPanelActivation) {
                Text("Clear Search When Opening Clipboard History")
            }

            Toggle(isOn: $viewModel.requireCmdToDelete) {
                Text("Require Cmd+Backspace to Delete")
            }

            Picker(xcstringsLocalized("Default Text Format", locale: locale), selection: $viewModel.pasteTextFormat) {
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
        } header: {
            SettingsSectionHeader(title: "Interface")
        } footer: {
            SettingsSectionFooter {
                Text("Display preset category tabs like Text, Links, and Images in the navigation bar.")
            }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync via iCloud")
                    Text("Seamlessly sync clipboard history across all Macs signed in with the same Apple ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    .foregroundStyle(runtimeStore.isSyncing ? .secondary : Color.accentColor)
                    .disabled(runtimeStore.isSyncing)
                }

                diagnosticsPanel
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
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
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

    private func xcstringsLocalized(_ key: String, locale: Locale) -> String {
        let bcp47 = locale.identifier(.bcp47)
        if let path = Bundle.main.path(forResource: bcp47, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        return String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(ClipboardRuntimeStore.shared)
}
