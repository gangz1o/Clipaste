import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Text("配置全局呼出快捷键")
                .font(.headline)
                .padding(.bottom, 10)
            
            HStack {
                Text("呼出/隐藏剪贴板：")
                KeyboardShortcuts.Recorder(for: .toggleClipboardPanel)
            }
            .padding(.bottom, 5)
            
            Text("提示：你可以随时使用此快捷键在任何应用中呼出历史记录。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    ShortcutsSettingsView()
        .environmentObject(SettingsViewModel())
}
