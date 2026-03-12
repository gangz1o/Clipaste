import SwiftUI
import KeyboardShortcuts

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
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
                Label(tab.rawValue, systemImage: tab.iconName)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 180)
            .listStyle(.sidebar)
            .tint(.accentColor)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
                    .navigationTitle("通用")
            case .shortcuts:
                ShortcutsSettingsView()
                .navigationTitle("快捷键")
            case .advanced:
                AdvancedSettingsView()
                    .navigationTitle("高级")
            case .about:
                AboutSettingsView()
                    .navigationTitle("关于")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity, minHeight: 420, idealHeight: 460, maxHeight: .infinity)
        .background(SettingsWindowObserver())
    }
}
