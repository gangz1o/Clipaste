import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @AppStorage("enable_smart_groups") private var isSmartGroupsEnabled: Bool = true
    @State private var showsDiagnostics = false
    @State private var copiedDiagnostics = false

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

            // ── Interface ──
            Section {
                Toggle("显示智能分组", isOn: $isSmartGroupsEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("Interface")
            } footer: {
                Text("在主界面导航栏显示文本、链接、图片等预置智能分类标签。")
            }

            // ── iCloud 数据同步 ──
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: syncEnabledBinding) {
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
                    .disabled(runtimeStore.isSyncing)

                    // 当同步开启时，展现高级控制台面板
                    if runtimeStore.isSyncEnabled {
                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            // 状态指示器
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(syncStatusColor)
                                    .frame(width: 8, height: 8)
                                    .opacity(runtimeStore.isSyncing ? 0.5 : 1.0)
                                    .animation(
                                        runtimeStore.isSyncing
                                            ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                            : .default,
                                        value: runtimeStore.isSyncing
                                    )

                                syncStatusText
                            }

                            Spacer()

                            // 立即同步按钮
                            Button {
                                runtimeStore.refreshCurrentRoute()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                    .rotationEffect(Angle(degrees: runtimeStore.isSyncing ? 360 : 0))
                                    .animation(
                                        runtimeStore.isSyncing
                                            ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                                            : .default,
                                        value: runtimeStore.isSyncing
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(runtimeStore.isSyncing ? .secondary : .accentColor)
                            .disabled(runtimeStore.isSyncing)
                            .help("检查 iCloud 连接状态")
                        }
                    }

                    diagnosticsPanel
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

    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { runtimeStore.isSyncEnabled },
            set: { runtimeStore.setSyncEnabled($0) }
        )
    }

    private var syncStatusColor: Color {
        if runtimeStore.isSyncing { return .blue }
        if runtimeStore.syncError != nil { return .red }
        return .green
    }

    @ViewBuilder
    private var syncStatusText: some View {
        if runtimeStore.isSyncing {
            Text("正在同步...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if let error = runtimeStore.syncError {
            Text("同步失败: \(error)")
                .font(.system(size: 12))
                .foregroundColor(.red)
        } else if let date = runtimeStore.lastSyncDate {
            Text("上次同步：\(date, format: .dateTime.month().day().hour().minute())")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else {
            Text("等待首次同步...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var diagnosticsPanel: some View {
        DisclosureGroup(isExpanded: $showsDiagnostics) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("活动路由")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.activeRoute == "cloud" ? "iCloud" : "本地")
                }

                HStack {
                    Text("当前开关状态")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.currentSyncEnabled ? "开启" : "关闭")
                }

                HStack {
                    Text("排队中的切换")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(pendingSyncDescription)
                }

                HStack {
                    Text("本地 Runtime")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.localRuntimeReady ? "已初始化" : "未初始化")
                }

                HStack {
                    Text("云 Runtime")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.cloudRuntimeReady ? "已初始化" : "未初始化")
                }

                HStack {
                    Text("Runtime Generation")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(runtimeStore.diagnosticsSnapshot.runtimeGeneration)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("本地 Store")
                        .foregroundColor(.secondary)
                    Text(runtimeStore.diagnosticsSnapshot.localStorePath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("云 Store")
                        .foregroundColor(.secondary)
                    Text(runtimeStore.diagnosticsSnapshot.cloudStorePath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let error = runtimeStore.diagnosticsSnapshot.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近错误")
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("最近事件")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(copiedDiagnostics ? "已复制" : "复制诊断信息") {
                            copyDiagnosticsToPasteboard()
                        }
                        .buttonStyle(.borderless)
                        .disabled(runtimeStore.diagnosticsEntries.isEmpty)
                    }

                    if runtimeStore.diagnosticsEntries.isEmpty {
                        Text("暂无事件记录")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(runtimeStore.diagnosticsEntries.prefix(8)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text(entry.level.rawValue)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(color(for: entry.level))

                                Text(entry.message)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("同步诊断")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.top, 2)
    }

    private var pendingSyncDescription: String {
        guard let pending = runtimeStore.diagnosticsSnapshot.pendingSyncEnabled else {
            return "无"
        }

        return pending ? "待开启" : "待关闭"
    }

    private func color(for level: ClipboardSyncDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func copyDiagnosticsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(runtimeStore.diagnosticsReport(), forType: .string)
        copiedDiagnostics = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedDiagnostics = false
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(ClipboardRuntimeStore.shared)
}
