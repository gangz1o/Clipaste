import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    @State private var showingClearAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("登录时打开 Clipaste", isOn: $viewModel.launchAtLogin)
                    .toggleStyle(.switch)

                Picker("语言", selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text("启动与语言")
            } footer: {
                Text("语言更改会在下次启动后完全生效。")
            }

            Section {
                Toggle("使用竖向列表布局", isOn: $viewModel.isVerticalLayout)
                    .toggleStyle(.switch)

                if viewModel.isVerticalLayout {
                    Picker("显示位置", selection: $viewModel.verticalFollowMode) {
                        ForEach(VerticalFollowMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            } header: {
                Text("窗口")
            } footer: {
                Text("横向卡片更适合浏览预览，竖向列表更适合快速切换与搜索。")
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isVerticalLayout)

            Section {
                Picker("保留时长", selection: $viewModel.historyRetention) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
            } header: {
                Text("历史记录")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()

                        Button(role: .destructive) {
                            showingClearAlert = true
                        } label: {
                            Label("清空历史记录…", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("永久删除所有剪贴板记录及相关图片缓存，且无法恢复。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .alert("确定要清空全部历史记录吗？", isPresented: $showingClearAlert) {
                Button("取消", role: .cancel) { }
                Button("彻底清空", role: .destructive) {
                    StorageManager.shared.clearAllHistory()
                }
            } message: {
                Text("此操作将永久删除所有剪贴板记录及相关图片缓存，且无法恢复。")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsViewModel())
}
