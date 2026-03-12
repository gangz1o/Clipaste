import SwiftUI
import Combine

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var highlightedItemId: UUID? = nil
    @Published var quickLookItem: ClipboardItem? = nil  // 空格键预览
    // 旧分组（横版 UI 使用的固定分组，保留兼容）
    @Published var groups: [ClipboardGroup] = []
    @Published var selectedGroupID: UUID? = nil
    // 新自定义分组
    @Published var customGroups: [ClipboardGroupItem] = []
    @Published var selectedGroupId: String? = nil

    private let clipboardMonitor: ClipboardMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(clipboardMonitor: ClipboardMonitor? = nil) {
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor.shared

        // 保留旧的固定分组（横版 UI 兼容）
        self.groups = [
            ClipboardGroup(id: UUID(), name: "链接", iconName: "link")
        ]

        NotificationCenter.default.publisher(for: .clipboardDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)

        loadData()
        loadCustomGroups()
        self.clipboardMonitor.startMonitoring()
        triggerAutoCleanup()
    }

    // MARK: - Auto Cleanup

    func triggerAutoCleanup() {
        let retentionRaw = UserDefaults.standard.string(forKey: "historyRetention") ?? HistoryRetention.oneMonth.rawValue
        guard let retention = HistoryRetention(rawValue: retentionRaw),
              let expirationDate = retention.expirationDate else { return }

        // Defer cleanup so initial UI load and the first clipboard writes do not contend
        // with the same SwiftData store during app startup.
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            StorageManager.shared.performAutoCleanup(before: expirationDate)
        }
    }

    func loadData() {
        let container = StorageManager.shared.container

        Task(priority: .userInitiated) {
            let searcher = ClipboardSearcher(modelContainer: container)
            let mappedItems = await searcher.searchAndMap(searchText: "")
            self.items = mappedItems

            if let highlightedItemId = self.highlightedItemId,
               mappedItems.contains(where: { $0.id == highlightedItemId }) == false {
                self.highlightedItemId = nil
            }
        }
    }

    func userDidSelect(item: ClipboardItem) {
        guard highlightedItemId != item.id else { return }
        highlightedItemId = item.id

        print("✅ 单击选中: \(item.id)")
    }

    /// 空格键快速预览：开/关切换。
    /// 如果正在预览则关闭；否则弹出当前高亮选中项的预览。
    func toggleQuickLook() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if quickLookItem != nil {
                quickLookItem = nil
            } else if let hid = highlightedItemId,
                      let item = filteredItems.first(where: { $0.id == hid }) {
                quickLookItem = item
            }
        }
    }

    /// 方向键导航：direction = +1 下/右，-1 上/左。
    func moveSelection(direction: Int) {
        let items = filteredItems
        guard !items.isEmpty else { return }

        let currentIndex = highlightedItemId.flatMap { hid in
            items.firstIndex(where: { $0.id == hid })
        }

        let nextIndex: Int
        if let idx = currentIndex {
            nextIndex = min(max(idx + direction, 0), items.count - 1)
        } else {
            // 没有选中项时：向下/右从 0 开始，向上/左从末尾开始
            nextIndex = direction > 0 ? 0 : items.count - 1
        }

        withAnimation(.easeInOut(duration: 0.1)) {
            highlightedItemId = items[nextIndex].id
        }
    }

    func selectGroup(_ groupID: UUID?) {
        selectedGroupID = groupID
        // 未来可以根据 selectedGroupID 进行数据 reload 和筛选
        loadData()
    }

    func addNewGroup() {
        print("触发添加新分组")
    }

    // MARK: - 自定义分组接口

    // 动态过滤后的列表数据
    var filteredItems: [ClipboardItem] {
        var result = items

        // 1. 先进行分组过滤
        if let groupId = selectedGroupId {
            result = result.filter { $0.groupId == groupId }
        }

        // 2. 再进行关键字实时过滤（忽略大小写）
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                let searchableText = (item.searchableText ?? item.rawText ?? item.textPreview).lowercased()
                if searchableText.contains(query) {
                    return true
                }

                if item.appName.lowercased().contains(query) {
                    return true
                }

                return false
            }
        }

        return result
    }

    func loadCustomGroups() {
        customGroups = StorageManager.shared.fetchAllGroups()
    }

    func createNewGroup(name: String, systemIconName: String = "folder") {
        StorageManager.shared.createGroup(name: name, systemIconName: systemIconName)
        // 延迟一帧后刷新，等 Actor 写完
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.loadCustomGroups()
        }
    }

    func assignItemToGroup(item: ClipboardItem, group: ClipboardGroupItem) {
        // 乐观 UI：直接更新内存中的 groupId
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].groupId = group.id
        }
        // 后台持久化
        StorageManager.shared.assignToGroup(hash: item.contentHash, groupId: group.id)
    }

    func renameGroup(group: ClipboardGroupItem, newName: String) {
        if let index = customGroups.firstIndex(where: { $0.id == group.id }) {
            customGroups[index] = ClipboardGroupItem(id: group.id, name: newName, systemIconName: group.systemIconName)
        }
        StorageManager.shared.renameGroup(id: group.id, newName: newName)
    }

    func deleteGroup(group: ClipboardGroupItem) {
        // 1. 如果正选中了要删的分组，立刻切回"全部"
        if selectedGroupId == group.id {
            selectedGroupId = nil
        }
        withAnimation {
            // 2. 从顶部导航中移除分组
            customGroups.removeAll(where: { $0.id == group.id })
            // 3. 乐观解绑：内存中属于该分组的记录回到"全部"（防 UI 状态错乱）
            for i in 0..<items.count {
                if items[i].groupId == group.id {
                    items[i].groupId = nil
                }
            }
        }
        // 4. 底层数据库真正执行删除 & 解绑
        StorageManager.shared.deleteGroup(id: group.id)
    }

    // MARK: - 右键菜单动作接口

    func pasteToActiveApp(item: ClipboardItem) {
        print("🚀 触发双击事件: \(item.id)")

        // 1. 先同步 UI 选中态
        userDidSelect(item: item)

        guard let record = StorageManager.shared.fetchRecord(id: item.id) else {
            print("❌ 未找到可复制的记录: \(item.id)")
            return
        }

        Task { @MainActor in
            // 2. 双击必须真实写入系统剪贴板
            let wroteToPasteboard = await PasteEngine.shared.writeToPasteboard(record: record)
            guard wroteToPasteboard else {
                print("❌ 写入系统剪贴板失败: \(item.id)")
                return
            }

            // 3. 隐藏面板，把焦点还给目标 App
            ClipboardPanelManager.shared.forceHidePanel()

            // 4. 根据设置决定是否自动触发粘贴
            let autoPaste = UserDefaults.standard.object(forKey: "autoPasteToActiveApp") as? Bool ?? true
            if autoPaste {
                guard PasteEngine.shared.checkAccessibilityPermissions() else {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    PasteEngine.shared.simulateCommandV()
                }
            } else {
                print("🛑 用户关闭了自动粘贴，仅执行复制并隐藏面板")
            }

            // 5. Respect "moveToTopAfterPaste" setting
            let moveToTop = UserDefaults.standard.bool(forKey: "moveToTopAfterPaste")
            if moveToTop {
                moveItemToTop(item)
            }
        }
    }

    func pasteAsPlainText(item: ClipboardItem) {
        ClipboardPanelManager.shared.hidePanel()
        guard let record = StorageManager.shared.fetchRecord(id: item.id),
              let text = record.plainText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // 面板已撤回，等屏幕咤啥后模拟 ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vKeyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vKeyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vKeyDown?.flags = .maskCommand
            vKeyUp?.flags   = .maskCommand
            vKeyDown?.post(tap: .cghidEventTap)
            vKeyUp?.post(tap: .cghidEventTap)
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        guard let record = StorageManager.shared.fetchRecord(id: item.id) else { return }

        Task { @MainActor in
            _ = await PasteEngine.shared.writeToPasteboard(record: record)
        }
    }

    func pinItem(item: ClipboardItem) {
        print("执行：固定/取消固定 - \(item.id)")
        // TODO: 持久化固定状态
    }

    func editItemContent(item: ClipboardItem) {
        print("执行：编辑内容 - \(item.id)")
    }

    func renameItem(item: ClipboardItem) {
        print("执行：重命名/添加标题 - \(item.id)")
    }

    func showPreview(item: ClipboardItem) {
        print("执行：预览 (Space) - \(item.id)")
    }

    func deleteItem(item: ClipboardItem) {
        // 1. 乐观 UI：立即从内存移除，卡片瞬间消失
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id }
        }
        if highlightedItemId == item.id {
            highlightedItemId = nil
        }
        // 2. 后台持久化：Actor 异步删除数据库记录
        StorageManager.shared.deleteRecord(hash: item.contentHash)
    }

    private func moveItemToTop(_ item: ClipboardItem) {
        // 1. 乐观 UI：立即把卡片移到最前，视觉上瞬间响应
        if let idx = items.firstIndex(where: { $0.id == item.id }), idx != 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                let moved = items.remove(at: idx)
                items.insert(moved, at: 0)
            }
        }
        // 保持高亮跟随
        highlightedItemId = item.id

        // 2. 持久化：Actor 刷新数据库时间戳，完成后广播 .clipboardDataDidChange
        //    ViewModel 的 Combine 订阅收到通知后会自动调用 loadData()，UI 再次排序与 DB 一致
        Task {
            await StorageManager.shared.moveItemToTop(id: item.id)
        }
    }
}
