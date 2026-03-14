import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHeaderView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @Environment(\.openSettings) private var openSettings
    @FocusState var isSearchFocused: Bool
    @AppStorage("isVerticalLayout") private var isVerticalLayout: Bool = false
    @AppStorage("isPanelPinned") private var isPanelPinned: Bool = false
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused: Bool = false
    @AppStorage("monitorInterval") private var monitorInterval: Double = 0.5
    @State private var isShowingNewGroupPopover = false
    @State private var newGroupName = ""
    @State private var newGroupIcon = "folder"
    @State private var showIconPicker = false
    @State private var targetedGroupId: String? = nil

    // MARK: - 重命名 / 删除分组弹窗控制
    @State private var groupToEdit: ClipboardGroupItem? = nil
    @State private var editGroupName: String = ""
    @State private var editGroupIcon: String = "folder"
    @State private var showEditPopover = false
    @State private var showEditIconPicker = false
    @State private var groupToDelete: ClipboardGroupItem? = nil
    @State private var showDeleteAlert = false

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
            hybridGroupBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    // MARK: - 横版模式：单行紧凑布局
    private var horizontalHeader: some View {
        HStack(spacing: 12) {
            // 固定按钮
            pinButton

            // 混合分组导航栏（自动占据左侧空间）
            hybridGroupBar

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search History…", text: $viewModel.searchInput)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
#if os(macOS)
                    .textContentType(.none)
#endif
                    .focused($isSearchFocused)

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

            Spacer()

            // 设置菜单
            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - 核心组件：混合优先级分组导航栏
    // 固定"全部" + 横向滚动极简 Tab + 固定溢出菜单
    private var hybridGroupBar: some View {
        HStack(spacing: 6) {
            // 1. 左侧固定："全部"按钮
            MinimalGroupTabButton(
                title: String(localized: "All"),
                icon: "tray.2.fill",
                isSelected: viewModel.selectedGroupId == nil
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.selectedGroupId = nil
                }
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            // 2. 中间滚动区域：用户自定义分组（免 Shift 横向滚动）
            FreeScrollWheelView {
                HStack(spacing: 4) {
                    ForEach(viewModel.customGroups) { group in
                        groupTabButton(group: group)
                    }
                }
                .padding(.horizontal, 2)
                .fixedSize(horizontal: true, vertical: false)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            // 3. 右侧固定：极简操作区（溢出菜单）
            Menu {
                // 列出所有分组，带 ✓ 标记
                Button(action: { viewModel.selectedGroupId = nil }) {
                    HStack {
                        Label(String(localized: "All"), systemImage: "tray.2.fill")
                        if viewModel.selectedGroupId == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !viewModel.customGroups.isEmpty { Divider() }

                ForEach(viewModel.customGroups) { group in
                    Button(action: {
                        withAnimation { viewModel.selectedGroupId = group.id }
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

                Divider()

                Button(action: {
                    newGroupName = ""
                    newGroupIcon = "folder"
                    isShowingNewGroupPopover = true
                }) {
                    Label(String(localized: "New Group…"), systemImage: "plus")
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
            .help(String(localized: "All Groups"))
            .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
                newGroupPopover
            }
        }
    }

    // MARK: - 单个分组 Tab 按钮（支持拖拽 & 右键管理）
    @ViewBuilder
    private func groupTabButton(group: ClipboardGroupItem) -> some View {
        let isSelected = viewModel.selectedGroupId == group.id
        let isDropTarget = targetedGroupId == group.id

        MinimalGroupTabButton(
            title: group.name,
            icon: group.systemIconName,
            isSelected: isSelected || isDropTarget,
            maxTextWidth: isVerticalLayout ? 60 : 80
        ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedGroupId = group.id
            }
        }
        .help(group.name)
        .onDrop(
            of: [.item],
            isTargeted: Binding(
                get: { targetedGroupId == group.id },
                set: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedGroupId = isTargeted ? group.id : nil
                    }
                }
            )
        ) { providers in
            let customUTI = "com.seedpilot.clipboard.item"
            if let provider = providers.first(where: { $0.registeredTypeIdentifiers.contains(customUTI) }) {
                provider.loadDataRepresentation(forTypeIdentifier: customUTI) { data, _ in
                    if let data, let idString = String(data: data, encoding: .utf8),
                       let uuid = UUID(uuidString: idString) {
                        DispatchQueue.main.async {
                            if let draggedItem = viewModel.items.first(where: { $0.id == uuid }) {
                                viewModel.assignItemToGroup(item: draggedItem, group: group)
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
        .help(isPanelPinned ? "Unpin Panel" : "Pin Panel")
    }

    // MARK: - 设置下拉菜单
    private var settingsMenu: some View {
        Menu {
            Button(action: { isMonitoringPaused.toggle() }) {
                Text(isMonitoringPaused ? "Resume Monitoring" : "Stop Monitoring")
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

            Button("Launch at Login (Coming Soon)") {}
                .disabled(true)

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
                TextField("Search…", text: $viewModel.searchInput)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
#if os(macOS)
                    .textContentType(.none)
#endif
                    .focused($isSearchFocused)
                if !viewModel.searchInput.isEmpty {
                    Button(action: { viewModel.searchInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 右侧：设置菜单
            settingsMenu
        }
    }

    // MARK: - 新建分组弹窗
    private var newGroupPopover: some View {
        VStack(spacing: 12) {
            Text("New Group")
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
                        Image(systemName: newGroupIcon)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 15))
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    GroupIconPicker(selectedIcon: $newGroupIcon)
                }

                TextField("Group Name", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
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
            Text("Edit Group")
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
                        Image(systemName: editGroupIcon)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 15))
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEditIconPicker) {
                    GroupIconPicker(selectedIcon: $editGroupIcon)
                }

                TextField("Group Name", text: $editGroupName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
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
}

#Preview {
    let dummyViewModel = ClipboardViewModel(clipboardMonitor: nil)
    return ClipboardHeaderView(viewModel: dummyViewModel)
        .frame(width: 380)
}

// MARK: - 极简原生 Tab 按钮子组件

struct MinimalGroupTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var maxTextWidth: CGFloat? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .if(maxTextWidth != nil) { view in
                        view.frame(maxWidth: maxTextWidth!, alignment: .leading)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
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
final class _FreeScrollNSScrollView: NSScrollView {
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
