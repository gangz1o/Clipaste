import SwiftUI
import Combine

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var groups: [ClipboardGroup] = []
    @Published var selectedGroupID: UUID? = nil

    private let clipboardMonitor: ClipboardMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(clipboardMonitor: ClipboardMonitor? = nil) {
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor.shared

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
}
