import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
            
            RulesSettingsView()
                .tabItem {
                    Label("规则", systemImage: "nosign")
                }
        }
        .frame(width: 450, height: 250)
    }
}

#Preview {
    AppSettingsView()
        .environmentObject(SettingsViewModel())
}
