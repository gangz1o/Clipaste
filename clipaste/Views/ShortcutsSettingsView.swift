import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示或隐藏剪贴板面板")
                        Text("从任何应用快速唤起 Clipaste。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    KeyboardShortcuts.Recorder(for: .toggleClipboardPanel)
                }
                .padding(.vertical, 2)
            } header: {
                Text("全局快捷键")
            } footer: {
                Text("如果快捷键无法生效，请在“系统设置 > 隐私与安全性 > 辅助功能”中允许 Clipaste 控制你的电脑。")
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
