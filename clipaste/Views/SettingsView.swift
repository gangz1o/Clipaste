import SwiftUI
import KeyboardShortcuts

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case shortcuts = "快捷键"
    case advanced = "高级"
    case about = "关于"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.iconName)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
                    .navigationTitle("通用")
            case .shortcuts:
                Form {
                    Section {
                        HStack {
                            Text("呼出 / 隐藏剪贴板面板")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .toggleClipboardPanel)
                        }
                    }
                    Section {
                        Text("提示：如果快捷键无法生效，请在\u{201C}系统设置 → 隐私与安全性 → 辅助功能\u{201D}中允许 clipaste 控制你的电脑。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .formStyle(.grouped)
                .padding()
                .navigationTitle("快捷键")
                .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity,
                       minHeight: 300, alignment: .top)
            case .advanced:
                AdvancedSettingsView()
                    .navigationTitle("高级")
            case .about:
                Text("关于预留区")
                    .navigationTitle("关于")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 600, height: 420)
    }
}
