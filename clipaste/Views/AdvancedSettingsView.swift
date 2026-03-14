import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @StateObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        Form {
            // ── Paste ──
            Section {
                Toggle("Auto-Paste to Active App on Double-Click", isOn: $viewModel.autoPasteToActiveApp)
                    .toggleStyle(.switch)

                if viewModel.autoPasteToActiveApp {
                    Button("Open Accessibility Settings…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                            return
                        }

                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Paste")
            } footer: {
                Text("When disabled, double-clicking an item only copies it to the clipboard without sending the paste shortcut.")
            }

            // ── Sort & Behavior ──
            Section {
                Toggle("Move Item to Top After Pasting", isOn: $viewModel.moveToTopAfterPaste)
                    .toggleStyle(.switch)
            } header: {
                Text("Sort & Behavior")
            } footer: {
                Text("Useful when you repeatedly paste the same content.")
            }

            // ── Text Format ──
            Section {
                Picker("Default Text Format", selection: $viewModel.pasteTextFormat) {
                    ForEach(PasteTextFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Text Format")
            } footer: {
                Text("Hold Option and double-click to temporarily reverse the current text format setting.")
            }

            // ── iCloud 数据同步 ──
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $syncManager.isSyncEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通过 iCloud 同步")
                                .font(.system(size: 14, weight: .medium))

                            Text("在所有登录同一 Apple ID 的 Mac 设备间无缝同步您的剪贴板历史记录。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)

                    // 当同步开启时，展现高级控制台面板
                    if syncManager.isSyncEnabled {
                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            // 状态指示器
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(syncStatusColor)
                                    .frame(width: 8, height: 8)
                                    .opacity(syncManager.isSyncing ? 0.5 : 1.0)
                                    .animation(
                                        syncManager.isSyncing
                                            ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                            : .default,
                                        value: syncManager.isSyncing
                                    )

                                syncStatusText
                            }

                            Spacer()

                            // 立即同步按钮
                            Button {
                                syncManager.forceSync()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                    .rotationEffect(Angle(degrees: syncManager.isSyncing ? 360 : 0))
                                    .animation(
                                        syncManager.isSyncing
                                            ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                                            : .default,
                                        value: syncManager.isSyncing
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(syncManager.isSyncing ? .secondary : .accentColor)
                            .disabled(syncManager.isSyncing)
                            .help("立即同步")
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("数据同步")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }

    // MARK: - Helpers

    private var syncStatusColor: Color {
        if syncManager.isSyncing { return .blue }
        if syncManager.syncError != nil { return .red }
        return .green
    }

    @ViewBuilder
    private var syncStatusText: some View {
        if syncManager.isSyncing {
            Text("正在同步...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if let error = syncManager.syncError {
            Text("同步失败: \(error)")
                .font(.system(size: 12))
                .foregroundColor(.red)
        } else if let date = syncManager.lastSyncDate {
            Text("上次同步：\(date, format: .dateTime.month().day().hour().minute())")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else {
            Text("等待首次同步...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
}
