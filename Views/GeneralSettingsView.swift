import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                Toggle("开机时自动启动", isOn: $viewModel.launchAtLogin)
                Toggle("启用音效", isOn: $viewModel.enableSoundEffects)
            }
            .padding(.bottom, 10)
            
            Section {
                Picker("保留历史记录：", selection: $viewModel.historyCapacity) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.rawValue).tag(limit)
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.clearHistory()
                    } label: {
                        Text("清除所有历史记录...")
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsViewModel())
}
