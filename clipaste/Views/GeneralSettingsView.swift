import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                Toggle("开机启动", isOn: $viewModel.launchAtLogin)
                    .toggleStyle(.switch)
                
                Picker("语言设置", selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }
            
            Section {
                Toggle("剪切板竖屏模式", isOn: $viewModel.isVerticalLayout)
                    .toggleStyle(.switch)
                
                if viewModel.isVerticalLayout {
                    Picker("竖屏跟随", selection: $viewModel.verticalFollowMode) {
                        ForEach(VerticalFollowMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isVerticalLayout)
            
            Section {
                Picker("剪切板保存历史", selection: $viewModel.historyRetention) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity, minHeight: 300, alignment: .top)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsViewModel())
}
