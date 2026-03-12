import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("双击后自动粘贴到当前应用", isOn: $viewModel.autoPasteToActiveApp)
                    .toggleStyle(.switch)

                if viewModel.autoPasteToActiveApp {
                    Button("打开“辅助功能”设置…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                            return
                        }

                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("粘贴")
            } footer: {
                Text("关闭后，双击条目只会将内容复制到系统剪贴板，不会自动发出粘贴快捷键。")
            }

            Section {
                Toggle("粘贴后将项目移至列表最前", isOn: $viewModel.moveToTopAfterPaste)
                    .toggleStyle(.switch)
            } header: {
                Text("排序与行为")
            } footer: {
                Text("适合频繁重复使用刚刚粘贴过的内容。")
            }

            Section {
                Picker("默认文本格式", selection: $viewModel.pasteTextFormat) {
                    ForEach(PasteTextFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("文本格式")
            } footer: {
                Text("按住 Option 键双击列表条目，可临时反转当前文本格式设置。")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
}
