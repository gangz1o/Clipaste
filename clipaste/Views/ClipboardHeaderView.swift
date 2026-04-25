import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHeaderView: View {
    private enum HorizontalSearchLayout {
        static let fieldHeight: CGFloat = 28
        static let collapsedWidth: CGFloat = fieldHeight
        static let expandedWidth: CGFloat = 240
        static let horizontalPadding: CGFloat = 12
        static let contentSpacing: CGFloat = 8
    }

    @ObservedObject var viewModel: ClipboardViewModel
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @FocusState var focusedField: ClipboardPanelFocusField?
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("isPanelPinned") private var isPanelPinned: Bool = false
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused: Bool = false
    @AppStorage("monitorInterval") private var monitorInterval: Double = 0.5
    @State private var isShowingNewGroupPopover = false
    @StateObject private var newGroupEditor = GroupEditorViewModel(mode: .create)
    @State private var targetedGroupId: String? = nil
    @State private var targetedBuiltInGroup: ClipboardBuiltInGroup? = nil
    @State private var groupTabFrames: [String: CGRect] = [:]
    @State private var reorderTarget: GroupReorderTarget? = nil
    @State private var isShowingGroupOverflowPopover = false

    // MARK: - 重命名 / 删除分组弹窗控制
    @State private var groupToEdit: ClipboardGroupItem? = nil
    @StateObject private var editGroupEditor = GroupEditorViewModel(mode: .edit)
    @State private var showEditPopover = false
    @State private var groupToDelete: ClipboardGroupItem? = nil
    @State private var showDeleteAlert = false

    /// 剪贴板面板上的 Popover 在独立窗口中呈现，往往拿不到根视图的 `\.locale`，需与 `ClipboardPanelRootView` 一致显式注入。
    private var panelLocale: Locale {
        appLanguage.resolvedLocale
    }

    private var isVerticalLayout: Bool {
        clipboardLayout == .vertical || clipboardLayout == .compact
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
        .padding(.bottom, isCompactMode ? 4 : 8)
        .background(headerBackground)
        .popover(isPresented: $showEditPopover, arrowEdge: .bottom) {
            editGroupPopover
                .environment(\.locale, panelLocale)
        }
        .onChange(of: isShowingNewGroupPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing)
        }
        .onChange(of: showEditPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing)
            if isShowing == false {
                groupToEdit = nil
            }
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
        VStack(spacing: isCompactMode ? 4 : 10) {
            // 第一行：固定按钮 + 搜索框 + 设置菜单
            searchBarContent

            // 第二行：混合分组导航栏（占满全部宽度）- 紧凑模式下隐藏
            if clipboardLayout != .compact {
                hybridGroupBar()
            }
        }
        .padding(.horizontal, isCompactMode ? 4 : 14)
        .padding(.top, isCompactMode ? 4 : 14)
        .padding(.bottom, isCompactMode ? 0 : 2)
    }

    private var isCompactMode: Bool {
        clipboardLayout == .compact
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
        !viewModel.customGroups.isEmpty || !viewModel.visibleSmartFilters.isEmpty || !viewModel.visibleBuiltInGroups.isEmpty
    }

    private var horizontalScrollableGroupTabsWidth: CGFloat {
        let customGroupWidth = CGFloat(viewModel.customGroups.count) * 72
        let smartFilterWidth = CGFloat(viewModel.visibleSmartFilters.count) * 70
        let builtInGroupWidth = CGFloat(viewModel.visibleBuiltInGroups.count) * 76
        let customAndBuiltInDividerWidth: CGFloat =
            (!viewModel.customGroups.isEmpty && !viewModel.visibleBuiltInGroups.isEmpty) ? 14 : 0
        let builtInAndSmartDividerWidth: CGFloat =
            (!viewModel.visibleBuiltInGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty) ? 14 : 0

        return min(
            680,
            customGroupWidth
                + builtInGroupWidth
                + smartFilterWidth
                + customAndBuiltInDividerWidth
                + builtInAndSmartDividerWidth
        )
    }

    private var horizontalLeadingControls: some View {
        HStack(spacing: 0) {
            pinButton
        }
        .frame(width: 28, alignment: .leading)
    }

    private var isHorizontalSearchExpanded: Bool {
        focusedField == .searchBar || !viewModel.searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var horizontalSearchBarWidth: CGFloat {
        isHorizontalSearchExpanded
            ? HorizontalSearchLayout.expandedWidth
            : HorizontalSearchLayout.collapsedWidth
    }

    private var horizontalSearchContentWidth: CGFloat {
        isHorizontalSearchExpanded
            ? HorizontalSearchLayout.expandedWidth - HorizontalSearchLayout.fieldHeight
            : 0
    }

    private var horizontalSearchWidthAnimation: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
    }

    private var horizontalSearchContentAnimation: Animation {
        .easeOut(duration: 0.18)
    }

    private var horizontalSearchBar: some View {
        HStack(spacing: 0) {
            Button(action: activateHorizontalSearch) {
                horizontalSearchIcon
                    .frame(
                        width: HorizontalSearchLayout.fieldHeight,
                        height: HorizontalSearchLayout.fieldHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: HorizontalSearchLayout.contentSpacing) {
                horizontalSearchTextField
                horizontalSearchClearButton
            }
            .padding(.leading, isHorizontalSearchExpanded ? 4 : 0)
            .padding(.trailing, isHorizontalSearchExpanded ? HorizontalSearchLayout.horizontalPadding : 0)
            .frame(width: horizontalSearchContentWidth, alignment: .leading)
            .opacity(isHorizontalSearchExpanded ? 1 : 0)
            .offset(x: isHorizontalSearchExpanded ? 0 : -4)
            .clipped()
            .allowsHitTesting(isHorizontalSearchExpanded)
            .animation(horizontalSearchContentAnimation, value: isHorizontalSearchExpanded)
        }
        .frame(height: HorizontalSearchLayout.fieldHeight)
        .frame(width: horizontalSearchBarWidth, alignment: .leading)
        .background(Color.clear.background(.regularMaterial))
        .overlay {
            Capsule()
                .strokeBorder(searchFieldFocusColor, lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: searchFieldShadowColor, radius: focusedField == .searchBar ? 8 : 4, y: 2)
        .animation(horizontalSearchWidthAnimation, value: isHorizontalSearchExpanded)
        .animation(.easeInOut(duration: 0.18), value: viewModel.searchInput.isEmpty)
        .help(isHorizontalSearchExpanded ? Text("Search History") : Text("Search"))
    }

    private var horizontalSearchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var horizontalSearchTextField: some View {
        TextField("Search History…", text: searchTextBinding)
            .font(.system(size: 13))
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
#if os(macOS)
            .textContentType(.none)
#endif
            .tint(appAccentColor.color)
            .focused($focusedField, equals: .searchBar)
    }

    @ViewBuilder
    private var horizontalSearchClearButton: some View {
        if !viewModel.searchInput.isEmpty {
            Button(action: { viewModel.searchInput = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func activateHorizontalSearch() {
        withAnimation(horizontalSearchWidthAnimation) {
            focusedField = .searchBar
        }
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
            isSelected: viewModel.isAllScopeSelected,
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

        if !viewModel.customGroups.isEmpty && !viewModel.visibleBuiltInGroups.isEmpty {
            Divider()
                .frame(height: 16)
                .opacity(0.5)
        }

        ForEach(viewModel.visibleBuiltInGroups, id: \.self) { group in
            builtInGroupTabButton(group)
        }

        if !viewModel.visibleBuiltInGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty {
            Divider()
                .frame(height: 16)
                .opacity(0.5)
        }

        ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
            MinimalGroupTabButton(
                title: .localized(type.localizedFilterTitle),
                icon: type.systemImage,
                isSelected: viewModel.isSmartFilterSelected(type),
                horizontalPadding: groupTabHorizontalPadding,
                verticalPadding: groupTabVerticalPadding,
                iconSpacing: groupTabIconSpacing
            ) {
                selectSmartFilter(type)
            }
        }
    }

    private var groupOverflowMenu: some View {
        Button {
            isShowingGroupOverflowPopover = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 24)
        .help("All Groups")
        .popover(isPresented: $isShowingGroupOverflowPopover, arrowEdge: .bottom) {
            groupOverflowPopover
                .environment(\.locale, panelLocale)
        }
        .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
            newGroupPopover
                .environment(\.locale, panelLocale)
        }
    }

    private var groupOverflowPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            GroupOverflowSectionTitle("Built-in Groups")

            GroupOverflowRow(
                title: .localized(LocalizedStringResource("All")),
                icon: "tray.2.fill",
                isSelected: viewModel.isAllScopeSelected,
                accentColor: appAccentColor
            ) {
                performGroupOverflowAction(selectAllGroup)
            }

            if !viewModel.customGroups.isEmpty {
                Divider()
                    .padding(.vertical, 3)

                GroupOverflowSectionTitle("Groups")

                ForEach(viewModel.customGroups) { group in
                    GroupOverflowRow(
                        title: .verbatim(group.name),
                        icon: group.systemIconName,
                        isSelected: viewModel.isCustomGroupSelected(group.id),
                        accentColor: appAccentColor
                    ) {
                        performGroupOverflowAction {
                            selectCustomGroup(group.id)
                        }
                    }
                }
            }

            ForEach(viewModel.visibleBuiltInGroups, id: \.self) { group in
                GroupOverflowRow(
                    title: .localized(group.localizedTitle),
                    icon: group.systemImage,
                    isSelected: viewModel.isBuiltInGroupSelected(group),
                    accentColor: appAccentColor
                ) {
                    performGroupOverflowAction {
                        selectBuiltInGroup(group)
                    }
                }
            }

            ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
                GroupOverflowRow(
                    title: .localized(type.localizedFilterTitle),
                    icon: type.systemImage,
                    isSelected: viewModel.isSmartFilterSelected(type),
                    accentColor: appAccentColor
                ) {
                    performGroupOverflowAction {
                        selectSmartFilter(type)
                    }
                }
            }

            Divider()
                .padding(.vertical, 3)

            GroupOverflowRow(
                title: .localized(LocalizedStringResource("New Group…")),
                icon: "plus",
                isSelected: false,
                accentColor: appAccentColor
            ) {
                isShowingGroupOverflowPopover = false
                newGroupEditor.prepareForCreate()
                DispatchQueue.main.async {
                    isShowingNewGroupPopover = true
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 164)
    }

    private func performGroupOverflowAction(_ action: () -> Void) {
        action()
        isShowingGroupOverflowPopover = false
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
    private func builtInGroupTabButton(_ group: ClipboardBuiltInGroup) -> some View {
        let isSelected = viewModel.isBuiltInGroupSelected(group)
        let isDropTarget = targetedBuiltInGroup == group

        MinimalGroupTabButton(
            title: .localized(group.localizedTitle),
            icon: group.systemImage,
            isSelected: isSelected || isDropTarget,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectBuiltInGroup(group)
        }
        .help(Text(group.localizedTitle))
        .onDrop(
            of: [
                ClipboardDragType.item,
                UTType.image.identifier,
                UTType.fileURL.identifier
            ],
            isTargeted: Binding(
                get: { targetedBuiltInGroup == group },
                set: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedBuiltInGroup = isTargeted ? group : nil
                    }
                }
            )
        ) { providers in
            handleItemDrop(providers: providers) { draggedItem in
                viewModel.addItemToBuiltInGroup(item: draggedItem, group: group)
            }
        }
    }

    @ViewBuilder
    private func groupTabButton(group: ClipboardGroupItem) -> some View {
        let isSelected = viewModel.isCustomGroupSelected(group.id)
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
            handleItemDrop(providers: providers) { draggedItem in
                viewModel.assignItemToGroup(item: draggedItem, group: group)
            }
        }
        .contextMenu {
            Button {
                editGroupEditor.prepareForEditing(group: group)
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
            .fill(appAccentColor.color)
            .frame(width: 3, height: 22)
            .shadow(color: appAccentColor.color.opacity(0.35), radius: 4, y: 1)
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
                .foregroundStyle(isPanelPinned ? appAccentColor.color : .secondary)
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
                ClipboardPanelManager.shared.forceHidePanel(restoringPreviousApp: false)
                SettingsWindowCoordinator.open {
                    openSettings()
                }
            }

            Toggle("Launch at Login", isOn: launchAtLoginBinding)

            Divider()

            Button("About Clipaste") {
                NSApp.orderFrontStandardAboutPanel()
                ClipboardPanelManager.shared.forceHidePanel(restoringPreviousApp: false)
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
    private var newGroupPopover: some View {
        GroupEditorPopover(viewModel: newGroupEditor) { name, iconName in
            commitNewGroup(name: name, iconName: iconName)
        }
    }

    private func commitNewGroup(name: String, iconName: String?) {
        viewModel.createNewGroup(name: name, systemIconName: iconName)
        isShowingNewGroupPopover = false
    }

    // MARK: - 编辑分组弹窗（支持修改名称 + 图标）
    private var editGroupPopover: some View {
        GroupEditorPopover(viewModel: editGroupEditor) { name, iconName in
            commitEditGroup(name: name, iconName: iconName)
        }
    }

    private func commitEditGroup(name: String, iconName: String?) {
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

    private func updatePopoverInputState(isShowing: Bool) {
        TypeToSearchService.shared.isPaused = isShowingNewGroupPopover || showEditPopover

        if isShowing {
            focusedField = nil
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.searchInput },
            set: { viewModel.searchInput = $0 }
        )
    }

    private var searchFieldFocusColor: Color {
        focusedField == .searchBar
            ? appAccentColor.color.opacity(0.34)
            : .clear
    }

    private var searchFieldShadowColor: Color {
        focusedField == .searchBar
            ? appAccentColor.color.opacity(0.16)
            : .black.opacity(0.05)
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

    private func selectBuiltInGroup(_ group: ClipboardBuiltInGroup) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.showBuiltInGroup(group)
        }
    }

    private func handleItemDrop(
        providers: [NSItemProvider],
        onResolvedItem: @escaping (ClipboardItem) -> Void
    ) -> Bool {
        if let draggedItemId = viewModel.draggedItemId,
           let draggedItem = viewModel.items.first(where: { $0.id == draggedItemId }) {
            onResolvedItem(draggedItem)
            viewModel.draggedItemId = nil
            return true
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(ClipboardDragType.item) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: ClipboardDragType.item) { data, _ in
            if let data,
               let idString = String(data: data, encoding: .utf8),
               let uuid = UUID(uuidString: idString) {
                DispatchQueue.main.async {
                    if let draggedItem = viewModel.items.first(where: { $0.id == uuid }) {
                        onResolvedItem(draggedItem)
                        viewModel.draggedItemId = nil
                    }
                }
            }
        }
        return true
    }
}

#Preview {
    ClipboardHeaderPreview()
}

private struct GroupOverflowSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GroupOverflowRow: View {
    enum Title {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: Title
    let icon: String?
    let isSelected: Bool
    let accentColor: AppAccentColor
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = ClipboardGroupIconName.normalize(icon) {
                    GroupIconView(iconName: iconName, size: 13)
                        .frame(width: 14, height: 14)
                } else {
                    Spacer()
                        .frame(width: 14, height: 14)
                }

                titleView
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isHighlighted ? accentColor.selectedContentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? accentColor.color : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch title {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let string):
            Text(verbatim: string)
        }
    }
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
    let icon: String?
    let isSelected: Bool
    var maxTextWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 5
    var iconSpacing: CGFloat = 5
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue

    var body: some View {
        Button(action: action) {
            HStack(spacing: resolvedIconName == nil ? 0 : iconSpacing) {
                if let resolvedIconName {
                    if IconPickerViewModel.customIconNames.contains(resolvedIconName) {
                        Image(resolvedIconName)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: resolvedIconName)
                            .frame(width: 11, height: 11)
                    }
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
            return AnyShapeStyle(appAccentColor.selectedContentColor)
        }
        return AnyShapeStyle(isHovered ? Color.primary : Color.secondary)
    }

    private var resolvedIconName: String? {
        ClipboardGroupIconName.normalize(icon)
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
            return AnyShapeStyle(appAccentColor.color)
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
            return AnyShapeStyle(appAccentColor.color.opacity(colorScheme == .dark ? 0.82 : 0.64))
        }

        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 1 : (isHovered ? 0.6 : 0)
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
            hostingView.rootView = content
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
