import SwiftUI

struct AdvancedSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            // ─── 粘贴行为 ───────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("粘贴至当前激活的 App", isOn: $viewModel.autoPasteToActiveApp)
                        .toggleStyle(.switch)
                    Text("双击卡片时，自动将内容直接写入目标应用，无需手动 ⌘V。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if viewModel.autoPasteToActiveApp {
                    Button("检查\u{201C}辅助功能\u{201D}权限…") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } header: {
                Text("粘贴行为")
            }

            // ─── 历史管理 ──────────────────────────────
            Section {
                Toggle("粘贴后将项目移至列表最前", isOn: $viewModel.moveToTopAfterPaste)
                    .toggleStyle(.switch)
            } header: {
                Text("历史管理")
            }

            // ─── 文本格式 ──────────────────────────────
            Section {
                Picker("文本粘贴默认格式", selection: $viewModel.pasteTextFormat) {
                    ForEach(PasteTextFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                Text("提示：在列表中按住 ⌥ Option 键双击，可临时反转此设置。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("文本格式")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity,
               minHeight: 300, alignment: .top)
    }
}
