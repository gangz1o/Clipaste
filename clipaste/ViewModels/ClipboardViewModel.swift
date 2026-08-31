import AppKit
import Combine
import Observation
import SwiftUI

extension Notification.Name {
    static let selectNextGroup = Notification.Name("selectNextGroup")
    static let selectPreviousGroup = Notification.Name("selectPreviousGroup")
    static let focusSearchFieldIntent = Notification.Name("focusSearchFieldIntent")
    static let focusListIntent = Notification.Name("focusListIntent")
    static let toggleFavoriteSelectionIntent = Notification.Name("toggleFavoriteSelectionIntent")
}

/// 统一分组标识：将智能分类和用户分组抹平为同一类型，供游标引擎使用。
/// UI 层绝不感知此枚举，仅 ViewModel 内部消费。
enum UnifiedGroupSlot: Equatable {
    case all
    case smartFilter(ClipboardContentType)
    case builtIn(ClipboardBuiltInGroup)
    case userGroup(String)
}

extension UserDefaults {
    @objc dynamic var enable_smart_groups: Bool {
        bool(forKey: "enable_smart_groups")
    }
}

@MainActor
@Observable
final class ClipboardViewModel {
    enum DataLoadMode {
        case visibleFirst
        case fullRefresh
    }

    static let initialVisibleItemBatchSize = 80
    static let backgroundPageBatchSize = 160
    /// 后台加载窗口上限：超过此值后停止后台分页，依赖搜索路径走 SQL 直查。
    /// 避免菜单栏应用把全部历史（数万条）常驻 in-memory items 数组。
    static let backgroundLoadMaxItems = 2000
    /// 数据库搜索分页大小。
    static let databaseSearchPageSize = 200

    struct QuickLookImagePreviewState {
        let image: NSImage
        let targetSize: CGSize
    }

    var items: [ClipboardItem] = [] {
        didSet { refreshFilterForDataOrScopeChange() }
    }
    var displayedItemIDs: [UUID] = []
    var searchInput: String = "" {
        didSet { scheduleFilterForSearchInput() }
    }
    var activeSearchQuery: String = ""
    var currentFilter: ClipboardContentType? = nil {
        didSet { refreshFilterForDataOrScopeChange() }
    }
    var selectedBuiltInGroup: ClipboardBuiltInGroup? = nil {
        didSet { refreshFilterForDataOrScopeChange() }
    }
    var selectedItemIDs: Set<UUID> = []
    var listScrollRequest: ClipboardListScrollRequest? = nil
    var isInitialHistoryLoading = false
    var isLoadingMoreHistory = false
    var lastSelectedID: UUID? = nil
    var quickLookItem: ClipboardItem? = nil
    var operationNotice: String? = nil
    var highResImage: NSImage? = nil
    var previewTargetSize: CGSize = .zero
    var sharingItem: ClipboardItem? = nil
    var draggedItemId: UUID? = nil
    var groups: [ClipboardGroup] = []
    var selectedGroupID: UUID? = nil
    var customGroups: [ClipboardGroupItem] = []
    var selectedGroupId: String? = nil {
        didSet { refreshFilterForDataOrScopeChange() }
    }
    var draggedGroup: ClipboardGroupItem? = nil
    var titleEditorItem: ClipboardItem? = nil
    var quickPasteModifier: ModifierKey = ModifierKey.quickPastePreference()
    var plainTextModifier: ModifierKey = ModifierKey.plainTextPreference()
    var isQuickPasteModifierHeld: Bool = false
    var isPlainTextModifierHeld: Bool = false
    var isSmartGroupsEnabled: Bool = UserDefaults.standard.object(forKey: "enable_smart_groups") as? Bool ?? true
    var pasteTextFormat: PasteTextFormat {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: "pasteTextFormat") else {
                return .original
            }
            return PasteTextFormat(rawValue: rawValue) ?? .original
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "pasteTextFormat")
        }
    }
    var panelFocusField: ClipboardPanelFocusField? = nil

    // Shared implementation state for the split partial ViewModel files.
    var cancellables: Set<AnyCancellable> = []
    var filterGeneration: UInt = 0
    @ObservationIgnored nonisolated(unsafe) var filterTask: Task<Void, Never>? = nil
    @ObservationIgnored nonisolated(unsafe) var searchDebounceTask: Task<Void, Never>? = nil
    var listScrollGeneration: UInt = 0
    @ObservationIgnored nonisolated(unsafe) var quickLookLoadTask: Task<Void, Never>? = nil
    var quickLookLoadGeneration: UInt = 0
    var quickLookRequestedItemID: UUID? = nil
    @ObservationIgnored nonisolated(unsafe) var autoPreviewTask: Task<Void, Never>? = nil
    var autoPreviewPendingItemID: UUID? = nil
    var autoPreviewPresentedItemID: UUID? = nil
    var shouldAutoSelectFirstItemAfterNextRefresh = false
    @ObservationIgnored nonisolated(unsafe) var keyDownMonitor: Any?
    @ObservationIgnored nonisolated(unsafe) var flagsChangedMonitor: Any?
    var currentModifierFlags: NSEvent.ModifierFlags = []
    var shouldResetSelectionToFirstDisplayedItem = false
    var hasPreparedPanelData = false
    var isPanelPresentationActive = false
    var needsReloadOnNextPresentation = false
    var dataLoadGeneration: UInt = 0
    var loadedHistoryCount = 0
    var hasLoadedFullHistory = false
    @ObservationIgnored nonisolated(unsafe) var historyLoadTask: Task<Void, Never>? = nil
    var itemIndexByID: [UUID: Int] = [:]
    var itemIndexByHash: [String: Int] = [:]
    @ObservationIgnored nonisolated(unsafe) var operationNoticeHideTask: Task<Void, Never>? = nil
    var suppressedPasteItemIDs: Set<UUID> = []
    let settingsViewModel: SettingsViewModel
    let aiSettingsViewModel: AISettingsViewModel

    init(
        clipboardMonitor _: ClipboardMonitor? = nil,
        settingsViewModel: SettingsViewModel? = nil,
        aiSettingsViewModel: AISettingsViewModel? = nil
    ) {
        self.settingsViewModel = settingsViewModel ?? SettingsViewModel.shared
        self.aiSettingsViewModel = aiSettingsViewModel ?? AISettingsViewModel.shared
        ModifierKey.migrateStoredPreferences()

        self.groups = [
            ClipboardGroup(id: UUID(), name: "链接", iconName: "link")
        ]

        setupDataSubscriptions()
        setupRecordChangeSubscriptions()
        setupWarmCacheSubscription()
        setupFilterPipeline()
        setupGroupSwitchSubscriptions()
        setupKeyboardIntentSubscriptions()
        setupSmartGroupsGuard()
        setupModifierPreferenceSync()
        hydrateFromWarmCacheIfAvailable()
    }

    deinit {
        operationNoticeHideTask?.cancel()
        filterTask?.cancel()
        searchDebounceTask?.cancel()
        autoPreviewTask?.cancel()
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
        }
        historyLoadTask?.cancel()
    }
}
