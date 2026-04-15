import KeyboardShortcuts
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

// MARK: - Shortcuts Settings View

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                globalShortcutsCard
                panelShortcutsCard
                modifiersCard
                resetButton
            }
            .padding(20)
        }
        .settingsScrollChromeHidden()
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 440, alignment: .top)
    }
}

// MARK: - Card 1: Global Shortcuts

private extension ShortcutsSettingsView {
    var globalShortcutsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCard(title: "Global Shortcuts", systemImage: "command") {
                VStack(spacing: 0) {
                    ShortcutRecorderRow("Show / Hide Clipboard Panel", name: .toggleClipboardPanel)
                }
            }

            Text("Only the wake shortcut is registered globally. Other actions work only while the Clipaste panel is focused.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Text("If the shortcut doesn't work, allow Clipaste in System Settings > Privacy & Security > Accessibility.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Card 2: Panel Shortcuts

private extension ShortcutsSettingsView {
    var panelShortcutsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCard(title: "Panel Shortcuts", systemImage: "rectangle.on.rectangle") {
                VStack(spacing: 0) {
                    ShortcutRecorderRow("Toggle Vertical Clipboard", name: .toggleVerticalClipboard)

                    cardDivider

                    ShortcutRecorderRow("Next List", name: .nextList)

                    cardDivider

                    ShortcutRecorderRow("Previous List", name: .prevList)

                    cardDivider

                    ShortcutRecorderRow("Toggle Favorites for Selection", name: .toggleFavoriteSelection)

                    cardDivider

                    ShortcutRecorderRow("Clear Clipboard History", name: .clearHistory)
                }
            }

            Text("These shortcuts are handled only when the Clipaste panel is the active window, so native shortcuts in Notes, browsers, Terminal, and other apps stay intact.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Card 3: Modifiers

private extension ShortcutsSettingsView {
    var modifiersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCard(title: "Modifier Keys", systemImage: "option") {
                VStack(spacing: 0) {
                    ModifierPickerView(
                        title: "Quick Paste",
                        suffix: "+ 1…9",
                        selection: $viewModel.quickPasteModifier
                    )

                    cardDivider

                    ModifierPickerView(
                        title: "Plain Text Mode",
                        suffix: "",
                        selection: $viewModel.plainTextModifier
                    )
                }
            }

            Text("Hold the quick paste modifier to reveal 1…9 shortcuts. Hold the plain text modifier while copying or pasting to strip formatting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Reset Button

private extension ShortcutsSettingsView {
    var resetButton: some View {
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
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
    }
}

// MARK: - Shared UI

private extension ShortcutsSettingsView {
    var cardDivider: some View {
        Divider()
            .padding(.vertical, 10)
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
        HStack {
            Text(title)
                .font(.body)

            Spacer()

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
        guard let defaultShortcut = name.defaultShortcut else {
            return false
        }

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
