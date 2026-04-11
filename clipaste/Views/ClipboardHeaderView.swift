import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHeaderView: View {
    private enum HeaderInputField: Hashable {
        case newGroupName
        case editGroupName
    }

    @ObservedObject var viewModel: ClipboardViewModel
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @FocusState var focusedField: ClipboardPanelFocusField?
    @FocusState private var focusedHeaderInput: HeaderInputField?
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @AppStorage("isPanelPinned") private var isPanelPinned: Bool = false
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused: Bool = false
    @AppStorage("monitorInterval") private var monitorInterval: Double = 0.5
    @State private var isShowingNewGroupPopover = false
    @State private var newGroupName = ""
    @State private var newGroupIcon = "folder"
    @State private var showIconPicker = false
    @State private var targetedGroupId: String? = nil
    @State private var groupTabFrames: [String: CGRect] = [:]
    @State private var reorderTarget: GroupReorderTarget? = nil

    // MARK: - 重命名 / 删除分组弹窗控制
    @State private var groupToEdit: ClipboardGroupItem? = nil
    @State private var editGroupName: String = ""
    @State private var editGroupIcon: String = "folder"
    @State private var showEditPopover = false
    @State private var showEditIconPicker = false
    @State private var groupToDelete: ClipboardGroupItem? = nil
    @State private var showDeleteAlert = false

    /// 剪贴板面板上的 Popover 在独立窗口中呈现，往往拿不到根视图的 `\.locale`，需与 `ClipboardPanelRootView` 一致显式注入。
    private var panelLocale: Locale {
        appLanguage.locale ?? .current
    }

    private var isVerticalLayout: Bool {
        clipboardLayout == .vertical
    }

    private var groupBarSpacing: CGFloat {
        isVerticalLayout ? 2 : 4
    }

    private var groupTabHorizontalPadding: CGFloat {
        isVerticalLayout ? 9 : 12
    }

    private var groupTabVerticalPadding: CGFloat {
        isVerticalLayout ? 4 : 5
    }

    private var groupTabIconSpacing: CGFloat {
        isVerticalLayout ? 4 : 5
    }

    var body: some View {
        Group {
            if isVerticalLayout {
                verticalHeader
            } else {
                horizontalHeader
            }
        }
        .padding(.bottom, 8)
        .background(headerBackground)
        .popover(isPresented: $showEditPopover, arrowEdge: .bottom) {
            editGroupPopover
                .environment(\.locale, panelLocale)
        }
        .onChange(of: isShowingNewGroupPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing, field: .newGroupName)
        }
        .onChange(of: showEditPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing, field: .editGroupName)
        }
        .onAppear {
            preferencesStore.refreshLaunchAtLoginStatus()
        }
        .alert("Delete Group", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let group = groupToDelete {
                    viewModel.deleteGroup(group: group)
                }
            }
        } message: {
            Text("The group's clipboard records will safely return to \"All\".")
        }
        .onChange(of: showDeleteAlert) { _, isShowing in
            ClipboardPanelManager.shared.suppressHide = isShowing
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if isVerticalLayout {
            WindowDragArea()
                .background(.regularMaterial)
        } else {
            Color.clear
        }
    }

    // MARK: - 竖版模式：双行布局
    private var verticalHeader: some View {
        VStack(spacing: 10) {
            // 第一行：固定按钮 + 搜索框 + 设置菜单
            searchBarContent

            // 第二行：混合分组导航栏（占满全部宽度）
            hybridGroupBar()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    // MARK: - 横版模式：单行紧凑布局
    private var horizontalHeader: some View {
        HStack(spacing: 0) {
            horizontalLeadingControls

            Spacer(minLength: 20)

            HStack(spacing: 6) {
                horizontalHybridGroupBar
                    .layoutPriority(1)

                horizontalSearchBar
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var hasHorizontalScrollableGroupTabs: Bool {
        !viewModel.customGroups.isEmpty || !viewModel.visibleSmartFilters.isEmpty
    }

    private var horizontalScrollableGroupTabsWidth: CGFloat {
        let customGroupWidth = CGFloat(viewModel.customGroups.count) * 72
        let smartFilterWidth = CGFloat(viewModel.visibleSmartFilters.count) * 70
        let mixedSectionDividerWidth: CGFloat =
            (!viewModel.customGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty) ? 14 : 0

        return min(680, customGroupWidth + smartFilterWidth + mixedSectionDividerWidth)
    }

    private var horizontalLeadingControls: some View {
        HStack(spacing: 0) {
            pinButton
        }
        .frame(width: 28, alignment: .leading)
    }

    private var horizontalSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search History…", text: searchTextBinding)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
#if os(macOS)
                .textContentType(.none)
#endif
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
        .frame(width: 240)
        .background(Color.clear.background(.regularMaterial))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var horizontalHybridGroupBar: some View {
        HStack(spacing: 4) {
            allGroupTabButton

            if hasHorizontalScrollableGroupTabs {
                FreeScrollWheelView {
                    scrollableGroupTabsStrip
                }
                .frame(width: horizontalScrollableGroupTabsWidth, alignment: .leading)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            groupOverflowMenu
        }
    }

    // MARK: - 核心组件：单行融合导航栏
    // 固定区域：[全部] … [溢出菜单 ⋯]
    // 可滚动区域：[智能分类…] │ [自定义分组…]
    private var allGroupTabButton: some View {
        MinimalGroupTabButton(
            title: .localized(LocalizedStringResource("All")),
            icon: "tray.2.fill",
            isSelected: viewModel.currentFilter == nil && viewModel.selectedGroupId == nil,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectAllGroup()
        }
    }

    private var scrollableGroupTabsStrip: some View {
        HStack(spacing: groupBarSpacing) {
            scrollableGroupTabsContent
        }
        .padding(.horizontal, isVerticalLayout ? 1 : 2)
        .fixedSize(horizontal: true, vertical: false)
        .coordinateSpace(.named(GroupBarDropSpace.name))
        .onPreferenceChange(GroupTabFramePreferenceKey.self) { frames in
            groupTabFrames = frames
        }
        .onDrop(
            of: [ClipboardDragType.group],
            delegate: GroupBarDropDelegate(
                orderedGroupIDs: viewModel.customGroups.map(\.id),
                groupFrames: groupTabFrames,
                reorderTarget: $reorderTarget,
                viewModel: viewModel
            )
        )
    }

    @ViewBuilder
    private var scrollableGroupTabsContent: some View {
        ForEach(viewModel.customGroups) { group in
            groupTabButton(group: group)
        }

        if !viewModel.customGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty {
            Divider()
                .frame(height: 16)
                .opacity(0.5)
        }

        ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
            MinimalGroupTabButton(
                title: .localized(type.localizedFilterTitle),
                icon: type.systemImage,
                isSelected: viewModel.currentFilter == type && viewModel.selectedGroupId == nil,
                horizontalPadding: groupTabHorizontalPadding,
                verticalPadding: groupTabVerticalPadding,
                iconSpacing: groupTabIconSpacing
            ) {
                selectSmartFilter(type)
            }
        }
    }

    private var groupOverflowMenu: some View {
        Menu {
            Text("Smart Filters")

            Button(action: {
                selectAllGroup()
            }) {
                HStack {
                    Label("All", systemImage: "tray.2.fill")
                    if viewModel.currentFilter == nil && viewModel.selectedGroupId == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
                Button(action: {
                    selectSmartFilter(type)
                }) {
                    HStack {
                        Label {
                            Text(type.localizedFilterTitle)
                        } icon: {
                            Image(systemName: type.systemImage)
                        }
                        if viewModel.currentFilter == type && viewModel.selectedGroupId == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if !viewModel.customGroups.isEmpty {
                Divider()
                Text("Groups")

                ForEach(viewModel.customGroups) { group in
                    Button(action: {
                        selectCustomGroup(group.id)
                    }) {
                        HStack {
                            Label(group.name, systemImage: group.systemIconName)
                            if viewModel.selectedGroupId == group.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: {
                newGroupName = ""
                newGroupIcon = "folder"
                isShowingNewGroupPopover = true
            }) {
                Label("New Group…", systemImage: "plus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("All Groups")
        .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
            newGroupPopover
                .environment(\.locale, panelLocale)
        }
    }

    @ViewBuilder
    private func hybridGroupBar() -> some View {
        HStack(spacing: groupBarSpacing) {
            allGroupTabButton

            if hasHorizontalScrollableGroupTabs {
                // “全部”固定在左侧，其余分组在独立滚动区域内横向滚动。
                FreeScrollWheelView {
                    scrollableGroupTabsStrip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            // ── 固定：溢出菜单 ⋯ ─────────────────────────────────
            groupOverflowMenu
        }
    }

    // MARK: - 单个分组 Tab 按钮（支持拖拽 & 右键管理）
    @ViewBuilder
    private func groupTabButton(group: ClipboardGroupItem) -> some View {
        let isSelected = viewModel.selectedGroupId == group.id
        let isDropTarget = targetedGroupId == group.id
        let insertionEdge = reorderTarget?.groupID == group.id ? reorderTarget?.edge : nil

        MinimalGroupTabButton(
            title: .verbatim(group.name),
            icon: group.systemIconName,
            isSelected: isSelected || isDropTarget,
            maxTextWidth: isVerticalLayout ? 60 : 80,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectCustomGroup(group.id)
        }
        .help(group.name)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: GroupTabFramePreferenceKey.self,
                        value: [group.id: proxy.frame(in: .named(GroupBarDropSpace.name))]
                    )
            }
        )
        .overlay(alignment: .leading) {
            if insertionEdge == .leading {
                groupInsertionIndicator
                    .offset(x: -4)
            }
        }
        .overlay(alignment: .trailing) {
            if insertionEdge == .trailing {
                groupInsertionIndicator
                    .offset(x: 4)
            }
        }
        .onDrag {
            reorderTarget = nil
            viewModel.draggedGroup = group
            let provider = NSItemProvider(object: group.id as NSString)
            provider.registerDataRepresentation(
                forTypeIdentifier: ClipboardDragType.group,
                visibility: .all
            ) { completion in
                completion(group.id.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [
                ClipboardDragType.item,
                UTType.image.identifier,
                UTType.fileURL.identifier
            ],
            isTargeted: Binding(
                get: { targetedGroupId == group.id },
                set: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedGroupId = isTargeted ? group.id : nil
                    }
                }
            )
        ) { providers in
            if let draggedItemId = viewModel.draggedItemId,
               let draggedItem = viewModel.items.first(where: { $0.id == draggedItemId }) {
                viewModel.assignItemToGroup(item: draggedItem, group: group)
                viewModel.draggedItemId = nil
                return true
            }

            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(ClipboardDragType.item) }) {
                provider.loadDataRepresentation(forTypeIdentifier: ClipboardDragType.item) { data, _ in
                    if let data, let idString = String(data: data, encoding: .utf8),
                       let uuid = UUID(uuidString: idString) {
                        DispatchQueue.main.async {
                            if let draggedItem = viewModel.items.first(where: { $0.id == uuid }) {
                                viewModel.assignItemToGroup(item: draggedItem, group: group)
                                viewModel.draggedItemId = nil
                            }
                        }
                    }
                }
                return true
            }
            return false
        }
        .contextMenu {
            Button {
                editGroupName = group.name
                editGroupIcon = group.systemIconName
                groupToEdit = group
                showEditPopover = true
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                groupToDelete = group
                showDeleteAlert = true
            } label: { Label("Delete Group", systemImage: "trash") }
        }
    }

    private var groupInsertionIndicator: some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor)
            .frame(width: 3, height: 22)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1)
            .allowsHitTesting(false)
    }

    // MARK: - 固定面板按钮
    private var pinButton: some View {
        Button(action: {
            isPanelPinned.toggle()
            NotificationCenter.default.post(
                name: NSNotification.Name("TogglePinStatus"),
                object: isPanelPinned
            )
        }) {
            Image(systemName: isPanelPinned ? "pin.fill" : "pin")
                .foregroundColor(isPanelPinned ? .accentColor : .secondary)
                .font(.system(size: 15))
                .rotationEffect(.degrees(isPanelPinned ? 45 : 0))
                .animation(.spring(), value: isPanelPinned)
        }
        .buttonStyle(.plain)
        .help(isPanelPinned ? Text("Unpin Panel") : Text("Pin Panel"))
    }

    // MARK: - 设置下拉菜单
    private var settingsMenu: some View {
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferencesStore.launchAtLogin },
            set: { preferencesStore.updateLaunchAtLogin($0) }
        )
    }

    // MARK: - 搜索栏（竖版模式使用）
    @ViewBuilder
    private var searchBarContent: some View {
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
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

            // 右侧：设置菜单
            settingsMenu
        }
    }

    // MARK: - 新建分组弹窗
    private var newGroupPopover: some View {
        VStack(spacing: 12) {
            Text("New Group").lineLimit(1).minimumScaleFactor(0.8)
                .font(.headline)

            HStack(spacing: 10) {
                // 图标选择按钮
                Button(action: { showIconPicker = true }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                         IconItemView(
                                    item: IconItem(name: newGroupIcon,
                                                   type: IconPickerViewModel.customIconNames.contains(newGroupIcon) ? .custom : .system,
                                                   displayName: newGroupIcon),
                                    size: 17
                                )
                                .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    GroupIconPicker(selectedIcon: $newGroupIcon)
                        .environment(\.locale, panelLocale)
                }

                TextField("Group Name", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .tint(.primary)
                    .frame(width: 150)
                    .focused($focusedHeaderInput, equals: .newGroupName)
                    .onSubmit { commitNewGroup() }
            }

            Button("Create") { commitNewGroup() }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.isEmpty)
        }
        .padding(16)
    }

    private func commitNewGroup() {
        guard !newGroupName.isEmpty else { return }
        viewModel.createNewGroup(name: newGroupName, systemIconName: newGroupIcon)
        isShowingNewGroupPopover = false
    }

    // MARK: - 编辑分组弹窗（支持修改名称 + 图标）
    private var editGroupPopover: some View {
        VStack(spacing: 12) {
            Text("Edit Group").lineLimit(1).minimumScaleFactor(0.8)
                .font(.headline)

            HStack(spacing: 10) {
                // 图标选择按钮
                Button(action: { showEditIconPicker = true }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                         IconItemView(
                                    item: IconItem(name: editGroupIcon,
                                                   type: IconPickerViewModel.customIconNames.contains(editGroupIcon) ? .custom : .system,
                                                   displayName: editGroupIcon),
                                    size: 17
                                )
                                .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEditIconPicker) {
                    GroupIconPicker(selectedIcon: $editGroupIcon)
                        .environment(\.locale, panelLocale)
                }

                TextField("Group Name", text: $editGroupName)
                    .textFieldStyle(.roundedBorder)
                    .tint(.primary)
                    .frame(width: 150)
                    .focused($focusedHeaderInput, equals: .editGroupName)
                    .onSubmit { commitEditGroup() }
            }

            Button("Save") { commitEditGroup() }
                .buttonStyle(.borderedProminent)
                .disabled(editGroupName.isEmpty)
        }
        .padding(16)
    }

    private func commitEditGroup() {
        guard let group = groupToEdit, !editGroupName.isEmpty else { return }
        if editGroupName != group.name {
            viewModel.renameGroup(group: group, newName: editGroupName)
        }
        // 重新获取更新后的 group（名称可能已改）
        let updatedGroup = viewModel.customGroups.first(where: { $0.id == group.id }) ?? group
        if editGroupIcon != updatedGroup.systemIconName {
            viewModel.updateGroupIcon(group: updatedGroup, newIcon: editGroupIcon)
        }
        showEditPopover = false
    }

    private func updatePopoverInputState(isShowing: Bool, field: HeaderInputField) {
        TypeToSearchService.shared.isPaused = isShowingNewGroupPopover || showEditPopover

        if isShowing {
            focusedField = nil
            DispatchQueue.main.async {
                focusedHeaderInput = field
            }
        } else if focusedHeaderInput == field {
            focusedHeaderInput = nil
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.searchInput },
            set: { viewModel.searchInput = $0 }
        )
    }

    private func selectAllGroup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.showAllItems()
        }
    }

    private func selectCustomGroup(_ groupID: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.showCustomGroup(groupID)
        }
    }

    private func selectSmartFilter(_ type: ClipboardContentType) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.showSmartFilter(type)
        }
    }
}

#Preview {
    ClipboardHeaderPreview()
}

private struct ClipboardHeaderPreview: View {
    @FocusState private var focusedField: ClipboardPanelFocusField?

    var body: some View {
        ClipboardHeaderView(
            viewModel: ClipboardViewModel(clipboardMonitor: nil),
            focusedField: _focusedField
        )
        .environmentObject(AppPreferencesStore.shared)
        .frame(width: 380)
    }
}

// MARK: - 极简原生 Tab 按钮子组件

struct MinimalGroupTabButton: View {
    enum Title {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: Title
    let icon: String
    let isSelected: Bool
    var maxTextWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 5
    var iconSpacing: CGFloat = 5
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: iconSpacing) {
                if IconPickerViewModel.customIconNames.contains(icon) {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: icon)
                        .frame(width: 11, height: 11)
                }
                Group {
                    switch title {
                    case .localized(let resource):
                        Text(resource)
                    case .verbatim(let string):
                        Text(verbatim: string)
                    }
                }
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .if(maxTextWidth != nil) { view in
                        view.frame(maxWidth: maxTextWidth!, alignment: .leading)
                    }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tabBackground)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.primary)
        }
        return AnyShapeStyle(isHovered ? Color.primary : Color.secondary)
    }

    private var tabBackground: some View {
        Capsule(style: .continuous)
            .fill(backgroundFillStyle)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderStyle, lineWidth: borderLineWidth)
            }
    }

    private var backgroundFillStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.10)
                    : Color.accentColor.opacity(0.10)
            )
        }

        if isHovered {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.045)
            )
        }

        return AnyShapeStyle(Color.clear)
    }

    private var borderStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.20)
            )
        }

        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 0.8 : (isHovered ? 0.6 : 0)
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - 免 Shift 横向滚动组件

/// 将垂直滚轮事件重定向为横向滚动的轻量级 NSScrollView 包装器。
/// 用于分组导航栏等窄小横向滚动区域，让用户无需按住 Shift 即可横向滚动。
struct FreeScrollWheelView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> _FreeScrollNSScrollView {
        let scrollView = _FreeScrollNSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        // 固定高度跟随容器，宽度自适应内容
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ nsView: _FreeScrollNSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            context.coordinator.scheduleRootViewUpdate(for: hostingView, rootView: content)
        }
    }

    static func dismantleNSView(_ nsView: _FreeScrollNSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingUpdate()
    }

    final class Coordinator {
        private var pendingUpdate: DispatchWorkItem?

        func scheduleRootViewUpdate<HostedContent: View>(
            for hostingView: NSHostingView<HostedContent>,
            rootView: HostedContent
        ) {
            pendingUpdate?.cancel()

            let workItem = DispatchWorkItem {
                hostingView.rootView = rootView
            }

            pendingUpdate = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func cancelPendingUpdate() {
            pendingUpdate?.cancel()
            pendingUpdate = nil
        }
    }
}

/// 自定义 NSScrollView：拦截垂直滚轮事件，转换为横向滚动。
/// 同时确保拖拽事件透传到子视图（SwiftUI .onDrop）。
final class _FreeScrollNSScrollView: NSScrollView {

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 注册内部拖拽类型，确保 NSScrollView 不会吞掉拖拽事件
        registerForDraggedTypes([
            .init(ClipboardDragType.item),
            .init(ClipboardDragType.group),
            .string
        ])
    }

    // MARK: - 拖拽透传：全部转发给 documentView (SwiftUI HostingView)
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return documentView?.draggingEntered(sender) ?? super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return documentView?.draggingUpdated(sender) ?? super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        documentView?.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return documentView?.prepareForDragOperation(sender) ?? super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return documentView?.performDragOperation(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        documentView?.concludeDragOperation(sender)
    }

    // MARK: - 滚轮重定向
    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        // 只在垂直分量主导时执行重定向
        guard abs(dy) > abs(dx), dy != 0 else {
            super.scrollWheel(with: event)
            return
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let delta = dy * multiplier

        let clipView = self.contentView
        var origin = clipView.bounds.origin
        origin.x -= delta

        // Clamp
        let documentWidth = self.documentView?.frame.width ?? 0
        let visibleWidth = clipView.bounds.width
        let maxX = max(0, documentWidth - visibleWidth)
        origin.x = max(0, min(origin.x, maxX))

        clipView.scroll(to: NSPoint(x: origin.x, y: clipView.bounds.origin.y))
        reflectScrolledClipView(clipView)
    }
}

private enum GroupInsertEdge {
    case leading
    case trailing
}

private struct GroupReorderTarget: Equatable {
    let groupID: String
    let edge: GroupInsertEdge
}

private enum GroupBarDropSpace {
    static let name = "ClipboardHeader.GroupBarDropSpace"
}

private struct GroupTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GroupBarDropDelegate: DropDelegate {
    let orderedGroupIDs: [String]
    let groupFrames: [String: CGRect]
    @Binding var reorderTarget: GroupReorderTarget?
    let viewModel: ClipboardViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [ClipboardDragType.group])
    }

    func dropEntered(info: DropInfo) {
        updateReorderPosition(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateReorderPosition(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard reorderTarget != nil else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            reorderTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.12)) {
            reorderTarget = nil
        }
        viewModel.draggedGroup = nil
        viewModel.saveGroupOrder()
        return true
    }

    private func updateReorderPosition(info: DropInfo) {
        guard let draggedGroup = viewModel.draggedGroup,
              let nextTarget = resolvedReorderTarget(at: info.location),
              draggedGroup.id != nextTarget.groupID else { return }

        if reorderTarget != nextTarget {
            withAnimation(.easeInOut(duration: 0.12)) {
                reorderTarget = nextTarget
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.moveGroup(
                from: draggedGroup.id,
                relativeTo: nextTarget.groupID,
                insertAfter: nextTarget.edge == .trailing
            )
        }
    }

    private func resolvedReorderTarget(at location: CGPoint) -> GroupReorderTarget? {
        guard let first = orderedFrames.first,
              let last = orderedFrames.last else { return nil }

        if location.x <= first.frame.midX {
            return GroupReorderTarget(groupID: first.id, edge: .leading)
        }

        for entry in orderedFrames {
            if location.x <= entry.frame.maxX {
                let edge: GroupInsertEdge = location.x <= entry.frame.midX ? .leading : .trailing
                return GroupReorderTarget(groupID: entry.id, edge: edge)
            }
        }

        return GroupReorderTarget(groupID: last.id, edge: .trailing)
    }

    private var orderedFrames: [(id: String, frame: CGRect)] {
        orderedGroupIDs.compactMap { id in
            guard let frame = groupFrames[id] else { return nil }
            return (id, frame)
        }
    }
}

// MARK: - Window Drag Handle

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    class DragHandleView: NSView {
        private var dragStart: NSPoint?

        override func mouseDown(with event: NSEvent) {
            dragStart = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStart, let window else { return }
            let current = event.locationInWindow
            let dx = current.x - start.x
            let dy = current.y - start.y
            var origin = window.frame.origin
            origin.x += dx
            origin.y += dy
            window.setFrameOrigin(origin)
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
        }

        override func draw(_ dirtyRect: NSRect) {}
    }
}
