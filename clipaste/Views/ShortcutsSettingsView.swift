import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    @AppStorage("modifier_quick_paste") private var quickPasteModifier: String = "⌘ Command"
    @AppStorage("modifier_plain_text") private var plainTextModifier: String = "⇧ Shift"

    var body: some View {
        Form {
            // ── 全局唤醒 ──
            Section {
                ShortcutRecorderRow("Show / Hide Clipboard Panel", name: .toggleClipboardPanel)
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("If the shortcut doesn't work, allow Clipaste in System Settings > Privacy & Security > Accessibility.")
            }

            // ── 导航与操作 ──
            Section {
                ShortcutRecorderRow("Next List", name: .nextList)
                ShortcutRecorderRow("Previous List", name: .prevList)
                ShortcutRecorderRow("Clear Clipboard History", name: .clearHistory)
            } header: {
                Text("Navigation & Actions")
            }

            // ── 修饰键 ──
            Section {
                ModifierPickerView(
                    title: String(localized: "Quick Paste"),
                    suffix: "+ 1…9",
                    selection: $quickPasteModifier,
                    options: ["⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift"]
                )
                ModifierPickerView(
                    title: String(localized: "Plain Text Mode"),
                    suffix: "",
                    selection: $plainTextModifier,
                    options: ["⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift"]
                )
            } header: {
                Text("Modifier Keys")
            } footer: {
                Text("Hold the modifier key while clicking an item to trigger the corresponding action.")
            }

            // ── 重置 ──
            Section {
                HStack {
                    Spacer()
                    Button(String(localized: "Reset Shortcuts to Defaults")) {
                        KeyboardShortcuts.reset(
                            .toggleClipboardPanel,
                            .nextList,
                            .prevList,
                            .clearHistory
                        )
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
                }
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }
}

#Preview {
    ShortcutsSettingsView()
}

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
        LabeledContent {
            HStack(spacing: 8) {
                shortcutRecorder

                if name.defaultShortcut != nil {
                    Button {
                        KeyboardShortcuts.reset(name)
                        shortcut = name.shortcut
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(String(localized: "Restore Default Shortcut"))
                    .accessibilityLabel(Text("Restore Default Shortcut"))
                    .disabled(!canRestoreDefault)
                }

            }
        } label: {
            Text(title)
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
        .overlay(alignment: .trailing) {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 28, height: 22)
                .padding(.trailing, 6)
                .allowsHitTesting(false)
        }
    }
}
