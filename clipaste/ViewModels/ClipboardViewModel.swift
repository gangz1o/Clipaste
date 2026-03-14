import SwiftUI
import Combine

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var filteredItems: [ClipboardItem] = []
    @Published var searchInput: String = ""
    @Published var activeSearchQuery: String = ""
    @Published var highlightedItemId: UUID? = nil
    @Published var quickLookItem: ClipboardItem? = nil  // 空格键预览
    @Published var sharingItem: ClipboardItem? = nil     // 右键分享错点
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
        setupFilterPipeline()
    }

    // MARK: - Combine 防抖搜索管道

    private func setupFilterPipeline() {
        // 搜索词变化：防抖 200ms，避免高频输入时大量无意义过滤
        let debouncedSearch = $searchInput
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)

        // 数据源 / 分组变化：立即响应
        let dataChanges = Publishers.CombineLatest($items, $selectedGroupId)

        Publishers.CombineLatest(debouncedSearch, dataChanges)
            .sink { [weak self] (query, itemsAndGroup) in
                guard let self else { return }
                let (allItems, groupId) = itemsAndGroup
                // ⚠️ 防抖结束后才更新底层查询词，彻底切断输入时的重绘风暴
                self.activeSearchQuery = query
                self.performAsyncFilter(query: query, items: allItems, groupId: groupId)
            }
            .store(in: &cancellables)
    }

    private func performAsyncFilter(query: String, items: [ClipboardItem], groupId: String?) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 无搜索词且无分组 → 直接还原全部，避免线程切换开销
        if cleanQuery.isEmpty && groupId == nil {
            self.filteredItems = items
            return
        }

        // ⚠️ 丢入后台线程，绝不允许在主线程遍历几十 MB 文本
        DispatchQueue.global(qos: .userInitiated).async {
            var result = items

            // 1. 分组过滤
            if let gid = groupId {
                result = result.filter { $0.groupId == gid }
            }

            // 2. 关键字过滤（使用 range(of:options:) 底层高效匹配）
            if !cleanQuery.isEmpty {
                result = result.filter { item in
                    let searchable = item.searchableText ?? item.rawText ?? item.textPreview
                    if searchable.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                        return true
                    }
                    if item.appName.range(of: cleanQuery, options: [.caseInsensitive]) != nil {
                        return true
                    }
                    return false
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.filteredItems = result
            }
        }
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

    // filteredItems 已迁移为 @Published 存储属性 + Combine 异步管道

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
        guard let record = StorageManager.shared.fetchRecord(id: item.id),
              let text = record.plainText else { return }
        // 1. 纯文本写入系统剪贴板（抹除一切格式）
        PasteEngine.shared.writePlainTextToPasteboard(text: text)
        // 2. 强制隐藏面板（无视图钉），焦点归还目标 App
        ClipboardPanelManager.shared.forceHidePanel()
        // 3. 延迟发送 Cmd+V，确保面板完全关闭且目标 App 已获焦
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteEngine.shared.simulateCommandV()
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        guard let record = StorageManager.shared.fetchRecord(id: item.id) else { return }

        Task { @MainActor in
            _ = await PasteEngine.shared.writeToPasteboard(record: record)
            // 仅复制，不隐藏面板；播放音效作为操作反馈
            NSSound(named: "Pop")?.play()
        }
    }

    func pinItem(item: ClipboardItem) {
        let newPinState = !item.isPinned

        // 1. 乐观 UI：同步翻转 items + filteredItems 中的 isPinned
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned = newPinState
        }
        if let idx = filteredItems.firstIndex(where: { $0.id == item.id }) {
            filteredItems[idx].isPinned = newPinState
        }

        // 2. 后台持久化（不会发通知，不会触发 loadData）
        StorageManager.shared.togglePin(hash: item.contentHash, isPinned: newPinState)

        // 3. 音效反馈
        NSSound(named: "Pop")?.play()
    }

    func editItemContent(item: ClipboardItem) {
        print("执行：编辑内容 - \(item.id)")
    }

    func renameItem(item: ClipboardItem) {
        print("执行：重命名/添加标题 - \(item.id)")
    }

    func showPreview(item: ClipboardItem) {
        // 复用空格键预览机制：设置 quickLookItem 即可触发 QuickLook popover
        if quickLookItem?.id == item.id {
            quickLookItem = nil  // 再次点击则关闭
        } else {
            quickLookItem = item
        }
    }

    func shareItem(item: ClipboardItem) {
        // 设置 sharingItem，触发卡片上的 ShareAnchorView 在对应位置弹出原生分享菜单
        sharingItem = item
    }

    func deleteItem(item: ClipboardItem) {
        // 1. 乐观 UI：同步移除 items + filteredItems，必须在同一个动画事务内完成
        //    防止 Combine 管道在 items 变化后产生过渡状态导致 filteredItems 二次突变
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id }
            filteredItems.removeAll { $0.id == item.id }
        }
        if highlightedItemId == item.id {
            highlightedItemId = nil
        }
        if quickLookItem?.id == item.id {
            quickLookItem = nil
        }
        // 2. 后台持久化：Actor 异步删除数据库记录（不会发通知，不会触发 loadData）
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
