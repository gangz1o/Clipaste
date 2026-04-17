import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            globalShortcutsSection
            panelShortcutsSection
            modifiersSection
            resetSection
        }
        .settingsPageChrome()
    }
}

// MARK: - Section 1: Global Shortcuts

private extension ShortcutsSettingsView {
    var globalShortcutsSection: some View {
        Section {
            ShortcutRecorderRow("Show / Hide Clipboard Panel", name: .toggleClipboardPanel)
        } header: {
            SettingsSectionHeader(title: "Global Shortcuts")
        } footer: {
            SettingsSectionFooter {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Only the wake shortcut is registered globally. Other actions work only while the Clipaste panel is focused.")
                    Text("If the shortcut doesn't work, allow Clipaste in System Settings > Privacy & Security > Accessibility.")
                }
            }
        }
    }
}

// MARK: - Section 2: Panel Shortcuts

private extension ShortcutsSettingsView {
    var panelShortcutsSection: some View {
        Section {
            ShortcutRecorderRow("Toggle Vertical Clipboard", name: .toggleVerticalClipboard)
            ShortcutRecorderRow("Next List", name: .nextList)
            ShortcutRecorderRow("Previous List", name: .prevList)
            ShortcutRecorderRow("Toggle Favorites for Selection", name: .toggleFavoriteSelection)
            ShortcutRecorderRow("Clear Clipboard History", name: .clearHistory)
        } header: {
            SettingsSectionHeader(title: "Panel Shortcuts")
        } footer: {
            SettingsSectionFooter {
                Text("These shortcuts are handled only when the Clipaste panel is the active window, so native shortcuts in Notes, browsers, Terminal, and other apps stay intact.")
            }
        }
    }
}

// MARK: - Section 3: Modifier Keys

private extension ShortcutsSettingsView {
    var modifiersSection: some View {
        Section {
            ModifierPickerView(
                title: "Quick Paste",
                suffix: "+ 1…9",
                selection: $viewModel.quickPasteModifier
            )

            ModifierPickerView(
                title: "Plain Text Mode",
                suffix: "",
                selection: $viewModel.plainTextModifier
            )
        } header: {
            SettingsSectionHeader(title: "Modifier Keys")
        } footer: {
            SettingsSectionFooter {
                Text("Hold the quick paste modifier to reveal 1…9 shortcuts. Hold the plain text modifier while copying or pasting to strip formatting.")
            }
        }
    }
}

// MARK: - Section 4: Reset

private extension ShortcutsSettingsView {
    var resetSection: some View {
        Section {
            Button {
                KeyboardShortcuts.reset(
                    .toggleClipboardPanel,
                    .toggleVerticalClipboard,
                    .nextList,
                    .prevList,
                    .toggleFavoriteSelection,
                    .clearHistory
                )
            } label: {
                Label("Reset Shortcuts to Defaults", systemImage: "arrow.counterclockwise")
            }
        }
    }
}

// MARK: - Shortcut Recorder Row

private struct ShortcutRecorderRow: View {
    let title: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    @State private var shortcut: KeyboardShortcuts.Shortcut?

    init(_ title: LocalizedStringKey, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
        _shortcut = State(initialValue: name.shortcut)
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                shortcutRecorder

                if name.defaultShortcut != nil {
                    Button("Restore Default Shortcut", systemImage: "arrow.uturn.backward") {
                        KeyboardShortcuts.reset(name)
                        shortcut = name.shortcut
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!canRestoreDefault)
                }
            }
        }
    }

    private var canRestoreDefault: Bool {
        guard let defaultShortcut = name.defaultShortcut else { return false }
        return shortcut != defaultShortcut
    }

    private var shortcutRecorder: some View {
        KeyboardShortcuts.Recorder(for: name) { newShortcut in
            shortcut = newShortcut
        }
        .frame(minWidth: 140)
    }
}

#Preview {
    ShortcutsSettingsView()
        .environmentObject(SettingsViewModel())
}
