import SwiftUI
import Combine

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
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

        $searchText
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .clipboardDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)

        loadData()
        loadCustomGroups()
        self.clipboardMonitor.startMonitoring()
    }

    func loadData() {
        let currentSearchText = self.searchText
        let container = StorageManager.shared.container

        Task(priority: .userInitiated) {
            let searcher = ClipboardSearcher(modelContainer: container)
            let mappedItems = await searcher.searchAndMap(searchText: currentSearchText)
            self.items = mappedItems
        }
    }

    func userDidSelect(item: ClipboardItem) {
        ClipboardPanelManager.shared.hidePanel()

        guard let record = StorageManager.shared.fetchRecord(id: item.id) else {
            return
        }

        guard PasteEngine.shared.checkAccessibilityPermissions() else {
            return
        }

        Task { @MainActor in
            await PasteEngine.shared.paste(record: record)
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
        if let groupId = selectedGroupId {
            return items.filter { $0.groupId == groupId }
        }
        // selectedGroupId == nil 时展示全量数据
        return items
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
        // 1. Write back to system clipboard (select also triggers clipboard write)
        userDidSelect(item: item)

        // 2. Hide panel so focus returns to target app
        ClipboardPanelManager.shared.hidePanel()

        // 3. Respect "autoPasteToActiveApp" setting
        let autoPaste = UserDefaults.standard.object(forKey: "autoPasteToActiveApp") as? Bool ?? true
        if autoPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let src = CGEventSource(stateID: .hidSystemState)
                let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                vDown?.flags = .maskCommand
                vUp?.flags   = .maskCommand
                vDown?.post(tap: .cgAnnotatedSessionEventTap)
                vUp?.post(tap:   .cgAnnotatedSessionEventTap)
            }
        }

        // 4. Respect "moveToTopAfterPaste" setting (move record's timestamp to now)
        let moveToTop = UserDefaults.standard.bool(forKey: "moveToTopAfterPaste")
        if moveToTop {
            // Move the item to top by bumping its position in the in-memory list
            if let idx = items.firstIndex(where: { $0.id == item.id }), idx != 0 {
                withAnimation {
                    let moved = items.remove(at: idx)
                    items.insert(moved, at: 0)
                }
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
        guard let record = StorageManager.shared.fetchRecord(id: item.id),
              let text = record.plainText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        // 2. 后台持久化：Actor 异步删除数据库记录
        StorageManager.shared.deleteRecord(hash: item.contentHash)
    }
}
