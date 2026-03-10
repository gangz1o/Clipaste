import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("playSound") private var playSound: Bool = true
    @AppStorage("clipboardLayout") private var layoutMode: AppLayoutMode = .horizontal
    @AppStorage("pasteBehavior") private var pasteBehavior: PasteBehavior = .direct
    @AppStorage("pasteAsPlainText") private var pasteAsPlainText: Bool = false
    @AppStorage("historyLimit") private var historyLimit: HistoryLimit = .month

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
            pasteTab
                .tabItem {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
            
            shortcutsTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
            
            dataTab
                .tabItem {
                    Label("数据", systemImage: "clock")
                }
        }
        .frame(width: 450, height: 300)
    }
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("登录时打开", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        viewModel.toggleLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("播放音效", isOn: $playSound)
                
                Picker("剪贴板布局", selection: $layoutMode) {
                    ForEach(AppLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding(20)
    }

    private var pasteTab: some View {
        Form {
            Section {
                Picker("粘贴动作", selection: $pasteBehavior) {
                    ForEach(PasteBehavior.allCases) { behavior in
                        Text(behavior.rawValue).tag(behavior)
                    }
                }
                
                if pasteBehavior == .direct {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("直接粘贴需要开启“辅助功能”权限")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("检查权限状态") {
                                viewModel.requestAccessibilityPermission()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
                
                Toggle("始终以纯文本粘贴", isOn: $pasteAsPlainText)
            }
        }
        .padding(20)
    }
    
    private var shortcutsTab: some View {
        Form {
            Section(header: Text("全局唤醒")) {
                HStack {
                    Text("唤醒剪贴板:")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleClipboardPanel)
                }
                
                Text("在任何应用中按下此快捷键，即可呼出 clipaste 历史面板。")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(20)
    }

    private var dataTab: some View {
        Form {
            Section(header: Text("历史记录保留时间")) {
                Picker("", selection: $historyLimit) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.rawValue).tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text("超出时间的记录将被自动清理以释放存储空间。该功能目前仍在测试中。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(20)
    }
}

#Preview {
    SettingsView()
}
