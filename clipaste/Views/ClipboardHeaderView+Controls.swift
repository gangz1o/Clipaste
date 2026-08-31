import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    var pinButton: some View {
        Button(action: {
            isPanelPinned.toggle()
            NotificationCenter.default.post(
                name: NSNotification.Name("TogglePinStatus"),
                object: isPanelPinned
            )
        }) {
            Image(systemName: isPanelPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPanelPinned ? appAccentColor.color : .secondary)
                .font(.system(size: 15))
                .rotationEffect(.degrees(isPanelPinned ? 45 : 0))
                .animation(.spring(), value: isPanelPinned)
        }
        .buttonStyle(.plain)
        .help(isPanelPinned ? Text("Unpin Panel") : Text("Pin Panel"))
    }

    // MARK: - 设置下拉菜单
    var settingsMenu: some View {
        Menu {
            Button(action: { isMonitoringPaused.toggle() }) {
                Text(isMonitoringPaused ? "Resume Monitoring" : "Pause Monitoring")
            }

            Menu("Clipboard Monitoring Interval") {
                Button(action: { monitorInterval = 0.1 }) {
                    HStack {
                        Text("Very Frequent (0.1s)")
                        if monitorInterval == 0.1 { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { monitorInterval = 0.5 }) {
                    HStack {
                        Text("Frequent (0.5s)")
                        if monitorInterval == 0.5 { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { monitorInterval = 1.0 }) {
                    HStack {
                        Text("Normal (1s)")
                        if monitorInterval == 1.0 { Image(systemName: "checkmark") }
                    }
                }
            }

            Divider()

            Button("Settings…") {
                NotificationCenter.default.post(
                    name: NSNotification.Name("HidePanelForce"),
                    object: nil
                )
                SettingsWindowCoordinator.open {
                    openSettings()
                }
            }

            Toggle("Launch at Login", isOn: launchAtLoginBinding)

            Divider()

            Button("About Clipaste") {
                NSApp.orderFrontStandardAboutPanel()
                NotificationCenter.default.post(
                    name: NSNotification.Name("HidePanelForce"),
                    object: nil
                )
            }

            Button("Send Feedback") {
                if let url = URL(string: "mailto:your_email@example.com?subject=clipaste%20Feedback") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .foregroundColor(.secondary)
                .font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferencesStore.launchAtLogin },
            set: { preferencesStore.updateLaunchAtLogin($0) }
        )
    }

    // MARK: - 搜索栏（竖版模式使用）
    @ViewBuilder
    var searchBarContent: some View {
        HStack(spacing: 8) {
            // 左侧：固定面板按钮
            pinButton

            // 中间：搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search…", text: searchTextBinding)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
#if os(macOS)
                    .textContentType(.none)
#endif
                    .tint(appAccentColor.color)
                    .focused($focusedField, equals: .searchBar)
                if !viewModel.searchInput.isEmpty {
                    Button(action: { viewModel.searchInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Color.clear.background(.regularMaterial))
            .overlay {
                Capsule()
                    .strokeBorder(searchFieldFocusColor, lineWidth: 1)
            }
            .clipShape(Capsule())
            .shadow(color: searchFieldShadowColor, radius: focusedField == .searchBar ? 8 : 4, y: 2)

            // 右侧：设置菜单
            settingsMenu
        }
    }

    // MARK: - 新建分组弹窗
    var newGroupPopover: some View {
        GroupEditorPopover(viewModel: newGroupEditor) { name, iconName in
            commitNewGroup(name: name, iconName: iconName)
        }
    }

    func commitNewGroup(name: String, iconName: String?) {
        viewModel.createNewGroup(name: name, systemIconName: iconName)
        isShowingNewGroupPopover = false
    }

    // MARK: - 编辑分组弹窗（支持修改名称 + 图标）
    var editGroupPopover: some View {
        GroupEditorPopover(viewModel: editGroupEditor) { name, iconName in
            commitEditGroup(name: name, iconName: iconName)
        }
    }

    func commitEditGroup(name: String, iconName: String?) {
        guard let group = groupToEdit else { return }
        if name != group.name {
            viewModel.renameGroup(group: group, newName: name)
        }
        // 重新获取更新后的 group（名称可能已改）
        let updatedGroup = viewModel.customGroups.first(where: { $0.id == group.id }) ?? group
        if iconName != updatedGroup.systemIconName {
            viewModel.updateGroupIcon(group: updatedGroup, newIcon: iconName)
        }
        showEditPopover = false
    }

    func updatePopoverInputState(isShowing: Bool) {
        TypeToSearchService.shared.isPaused = isShowingNewGroupPopover || showEditPopover

        if isShowing {
            focusedField = nil
        }
    }

    var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.searchInput },
            set: { viewModel.searchInput = $0 }
        )
    }

    var searchFieldFocusColor: Color {
        focusedField == .searchBar
            ? appAccentColor.color.opacity(0.34)
            : .clear
    }

    var searchFieldShadowColor: Color {
        focusedField == .searchBar
            ? appAccentColor.color.opacity(0.16)
            : .black.opacity(0.05)
    }

    func selectAllGroup() {
        viewModel.showAllItems()
    }

    func selectCustomGroup(_ groupID: String) {
        viewModel.showCustomGroup(groupID)
    }

    func selectSmartFilter(_ type: ClipboardContentType) {
        viewModel.showSmartFilter(type)
    }

    func selectBuiltInGroup(_ group: ClipboardBuiltInGroup) {
        viewModel.showBuiltInGroup(group)
    }

}
