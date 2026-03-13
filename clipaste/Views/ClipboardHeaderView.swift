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
    @State private var showEditAlert = false
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
        .alert("Rename Group", isPresented: $showEditAlert) {
            TextField("Group Name", text: $editGroupName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let group = groupToEdit, !editGroupName.isEmpty {
                    viewModel.renameGroup(group: group, newName: editGroupName)
                }
            }
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

    // MARK: - 竖屏模式：两行布局
    private var verticalHeader: some View {
        VStack(spacing: 10) {
            searchBarContent
            groupPills
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    // MARK: - 横屏模式：单行布局
    private var horizontalHeader: some View {
        HStack(spacing: 8) {
            groupPills

            Spacer()

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
            .padding(.trailing, 16)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - 共享：搜索栏
    @ViewBuilder
    private var searchBarContent: some View {
        HStack(spacing: 8) {
            // 左侧：固定面板按钮
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

            // 右侧：原生系统下拉菜单
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
    }

    // MARK: - 共享：分组药丸导航栏
    @ViewBuilder
    private var groupPills: some View {
        let maxVisible = isVerticalLayout ? 4 : 5

        HStack(spacing: 8) {
            // ── "全部" 固定药丸 ──
            Button(action: { viewModel.selectedGroupId = nil }) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.2.fill")
                        .font(.system(size: 13, weight: viewModel.selectedGroupId == nil ? .semibold : .regular))
                    Text(String(localized: "All"))
                        .font(.system(size: 13, weight: viewModel.selectedGroupId == nil ? .semibold : .medium))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(viewModel.selectedGroupId == nil ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(viewModel.selectedGroupId == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.8))
                )
            }
            .buttonStyle(.plain)
            .help(String(localized: "All"))

            // ── 前 N 个分组药丸 ──
            ForEach(viewModel.customGroups.prefix(maxVisible)) { group in
                groupIconButton(group: group)
            }

            Spacer()

            // ── 溢出菜单 ──
            Menu {
                ForEach(viewModel.customGroups) { group in
                    Button {
                        viewModel.selectedGroupId = group.id
                    } label: {
                        Label(group.name, systemImage: group.systemIconName)
                    }
                }

                Divider()

                Button {
                    newGroupName = ""
                    newGroupIcon = "folder"
                    isShowingNewGroupPopover = true
                } label: {
                    Label(String(localized: "New Group"), systemImage: "plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
                newGroupPopover
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 单个分组药丸按钮
    @ViewBuilder
    private func groupIconButton(group: ClipboardGroupItem) -> some View {
        let isSelected = viewModel.selectedGroupId == group.id
        let isDropTarget = targetedGroupId == group.id

        Button(action: { viewModel.selectedGroupId = group.id }) {
            HStack(spacing: 6) {
                Image(systemName: group.systemIconName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor((isSelected || isDropTarget) ? .white : .secondary)
                Text(group.name)
                    .font(.system(size: 13, weight: (isSelected || isDropTarget) ? .semibold : .medium))
                    .foregroundColor((isSelected || isDropTarget) ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .frame(maxWidth: isVerticalLayout ? 50 : 80, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(iconBackground(selected: isSelected, dropTarget: isDropTarget))
            )
        }
        .buttonStyle(.plain)
        .help(group.name)
        .onDrop(
            of: [.plainText, .data],
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
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(customUTI) }) {
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
                groupToEdit = group
                showEditAlert = true
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                groupToDelete = group
                showDeleteAlert = true
            } label: { Label("Delete Group", systemImage: "trash") }
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

    // MARK: - 图标背景颜色
    private func iconBackground(selected: Bool, dropTarget: Bool) -> Color {
        if dropTarget { return Color.accentColor.opacity(0.8) }
        if selected { return Color.accentColor }
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }
}

#Preview {
    let dummyViewModel = ClipboardViewModel(clipboardMonitor: nil)
    return ClipboardHeaderView(viewModel: dummyViewModel)
        .frame(width: 380)
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
