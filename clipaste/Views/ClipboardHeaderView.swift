import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHeaderView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @FocusState var isSearchFocused: Bool
    @AppStorage("isVerticalLayout") private var isVerticalLayout: Bool = false
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
        .alert("重命名分组", isPresented: $showEditAlert) {
            TextField("分组名称", text: $editGroupName)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let group = groupToEdit, !editGroupName.isEmpty {
                    viewModel.renameGroup(group: group, newName: editGroupName)
                }
            }
        }
        .alert("删除分组", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let group = groupToDelete {
                    viewModel.deleteGroup(group: group)
                }
            }
        } message: {
            Text("确定要删除此分组吗？\n其中的剪贴板记录不会被删除，它们将安全地回到\u{201C}全部\u{201D}列表中。")
        }
    }

    // MARK: - 竖屏模式：两行布局
    private var verticalHeader: some View {
        VStack(spacing: 10) {
            // 第一行：图钉 + 搜索框 + 设置
            HStack(spacing: 10) {
                Button(action: { /* 预留图钉功能 */ }) {
                    Image(systemName: "pin")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("搜索历史记录...", text: $viewModel.searchText)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled(true)
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
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)

                Button(action: { /* 预留设置功能 */ }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 第二行：分组标签横向滚动
            groupPills
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 横屏模式：单行布局（原有）
    private var horizontalHeader: some View {
        HStack(spacing: 8) {
            // 左侧区域 (分组标签栏)
            groupPills

            Spacer()

            // 右侧区域 (精致搜索框)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("搜索历史记录...", text: $viewModel.searchText)
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
        .padding(.vertical, 12)
    }

    // MARK: - 共享：分组胶囊（三段式布局）
    @ViewBuilder
    private var groupPills: some View {
        HStack(spacing: 8) {

            // ==========================================
            // 1. 左侧固定区："全部" 按钮
            // ==========================================
            Button(action: { viewModel.selectedGroupId = nil }) {
                Text("全部")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(viewModel.selectedGroupId == nil ? .white : .primary)
                    .background(viewModel.selectedGroupId == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // ==========================================
            // 2. 中间弹性滚动区：自定义分组
            // ==========================================
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
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button(role: .destructive) {
                                groupToDelete = group
                                showDeleteAlert = true
                            } label: { Label("删除分组", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            // 渐变遮罩：边缘自然消隐，高级质感
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.1), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                }
            )

            // ==========================================
            // 3. 右侧固定区："+" 新建分组按钮
            // ==========================================
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
                    Text("新建分组").font(.headline)
                    TextField("输入分组名称", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit {
                            if !newGroupName.isEmpty {
                                viewModel.createNewGroup(name: newGroupName)
                                isShowingNewGroupPopover = false
                            }
                        }
                    Button("创建") {
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

    // MARK: - 胶囊颜色辅助（拆分以规避编译器类型检查超时）
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
