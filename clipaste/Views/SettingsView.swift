import SwiftUI
import KeyboardShortcuts

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "general"
    case shortcuts = "shortcuts"
    case advanced = "advanced"
    case about = "about"
    
    var id: String { self.rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }
    
    var navigationTitle: LocalizedStringKey { title }
    
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
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.iconName)
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
                    .navigationTitle("General")
            case .shortcuts:
                ShortcutsSettingsView()
                    .navigationTitle("Shortcuts")
            case .advanced:
                AdvancedSettingsView()
                    .navigationTitle("Advanced")
            case .about:
                AboutSettingsView()
                    .navigationTitle("About")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity, minHeight: 420, idealHeight: 460, maxHeight: .infinity)
        .background(SettingsWindowObserver())
        .background(WindowAppearanceObserver(theme: appTheme))
    }
}
