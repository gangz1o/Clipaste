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
        .overlay(
            Group {
                if isVerticalLayout {
                    Divider()
                }
            },
            alignment: .bottom
        )
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

                TextField("Search History…", text: $viewModel.searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
#if os(macOS)
                    .textContentType(.none)
#endif
                    .focused($isSearchFocused)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
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
                TextField("Search…", text: $viewModel.searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
#if os(macOS)
                    .textContentType(.none)
#endif
                    .focused($isSearchFocused)
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
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

    // MARK: - 共享：分组胶囊
    @ViewBuilder
    private var groupPills: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.selectedGroupId = nil }) {
                Text("All")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(viewModel.selectedGroupId == nil ? .white : .primary)
                    .background(viewModel.selectedGroupId == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.customGroups) { group in
                        Button(action: { viewModel.selectedGroupId = group.id }) {
                            HStack(spacing: 4) {
                                Text(group.name).font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(pillForeground(group: group))
                            .background(pillBackground(group: group))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .onDrop(
                            of: [.plainText],
                            isTargeted: Binding(
                                get: { targetedGroupId == group.id },
                                set: { isTargeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        targetedGroupId = isTargeted ? group.id : nil
                                    }
                                }
                            )
                        ) { providers in
                            if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
                                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                                    if let idString = object as? String,
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
                }
                .padding(.horizontal, 2)
            }
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.1), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                }
            )

            Button(action: {
                newGroupName = ""
                isShowingNewGroupPopover.toggle()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
                VStack(spacing: 12) {
                    Text("New Group").font(.headline)
                    TextField("Group Name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit {
                            if !newGroupName.isEmpty {
                                viewModel.createNewGroup(name: newGroupName)
                                isShowingNewGroupPopover = false
                            }
                        }
                    Button("Create") {
                        if !newGroupName.isEmpty {
                            viewModel.createNewGroup(name: newGroupName)
                            isShowingNewGroupPopover = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newGroupName.isEmpty)
                }
                .padding(16)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 胶囊颜色辅助
    private func pillForeground(group: ClipboardGroupItem) -> Color {
        if targetedGroupId == group.id || viewModel.selectedGroupId == group.id {
            return .white
        }
        return .primary
    }

    @ViewBuilder
    private func pillBackground(group: ClipboardGroupItem) -> some View {
        if targetedGroupId == group.id {
            Color.accentColor.opacity(0.8)
        } else if viewModel.selectedGroupId == group.id {
            Color.accentColor
        } else {
            Color.clear.background(.regularMaterial)
        }
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
