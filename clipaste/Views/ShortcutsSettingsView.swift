import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    @AppStorage("modifier_quick_paste") private var quickPasteModifier: String = "⌘ Command"
    @AppStorage("modifier_plain_text") private var plainTextModifier: String = "⇧ Shift"

    var body: some View {
        Form {
            // ── 全局唤醒 ──
            Section {
                KeyboardShortcuts.Recorder(
                    String(localized: "Show / Hide Clipboard Panel"),
                    name: .toggleClipboardPanel
                )
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("If the shortcut doesn't work, allow Clipaste in System Settings > Privacy & Security > Accessibility.")
            }

            // ── 导航与操作 ──
            Section {
                KeyboardShortcuts.Recorder(
                    String(localized: "Next List"),
                    name: .nextList
                )
                KeyboardShortcuts.Recorder(
                    String(localized: "Previous List"),
                    name: .prevList
                )
                KeyboardShortcuts.Recorder(
                    String(localized: "Clear Clipboard History"),
                    name: .clearHistory
                )
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
