import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let selectNextGroup = Notification.Name("selectNextGroup")
    static let selectPreviousGroup = Notification.Name("selectPreviousGroup")
    static let focusSearchFieldIntent = Notification.Name("focusSearchFieldIntent")
    static let focusListIntent = Notification.Name("focusListIntent")
}

/// 统一分组标识：将智能分类和用户分组抹平为同一类型，供游标引擎使用。
/// UI 层绝不感知此枚举，仅 ViewModel 内部消费。
enum UnifiedGroupSlot: Equatable {
    case all
    case smartFilter(ClipboardContentType)
    case userGroup(String)
}

extension UserDefaults {
    @objc dynamic var enable_smart_groups: Bool {
        bool(forKey: "enable_smart_groups")
    }
}

@MainActor
final class ClipboardViewModel: ObservableObject {
    enum DataLoadMode {
        case visibleFirst
        case fullRefresh
    }

    static let initialVisibleItemBatchSize = 80

    struct QuickLookImagePreviewState {
        let image: NSImage
        let targetSize: CGSize
    }

    @Published var items: [ClipboardItem] = []
    @Published var displayedItemIDs: [UUID] = []
    @Published var searchInput: String = ""
    @Published var activeSearchQuery: String = ""
    @Published var currentFilter: ClipboardContentType? = nil
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var isInitialHistoryLoading = false
    var lastSelectedID: UUID? = nil
    @Published var quickLookItem: ClipboardItem? = nil
    @Published var highResImage: NSImage? = nil
    @Published var previewTargetSize: CGSize = .zero
    @Published var sharingItem: ClipboardItem? = nil
    @Published var draggedItemId: UUID? = nil
    @Published var groups: [ClipboardGroup] = []
    @Published var selectedGroupID: UUID? = nil
    @Published var customGroups: [ClipboardGroupItem] = []
    @Published var selectedGroupId: String? = nil
    @Published var draggedGroup: ClipboardGroupItem? = nil
    @Published var quickPasteModifier: ModifierKey = ModifierKey.quickPastePreference()
    @Published var plainTextModifier: ModifierKey = ModifierKey.plainTextPreference()
    @Published var isQuickPasteModifierHeld: Bool = false
    @Published var isPlainTextModifierHeld: Bool = false
    @AppStorage("enable_smart_groups") var isSmartGroupsEnabled: Bool = true
    @AppStorage("pasteTextFormat") var pasteTextFormat: PasteTextFormat = .original
    var panelFocusField: ClipboardPanelFocusField? = nil

    // Shared implementation state for the split partial ViewModel files.
    var cancellables: Set<AnyCancellable> = []
    var filterGeneration: UInt = 0
    var quickLookLoadTask: Task<Void, Never>? = nil
    var quickLookLoadGeneration: UInt = 0
    var quickLookRequestedItemID: UUID? = nil
    nonisolated(unsafe) var keyDownMonitor: Any?
    nonisolated(unsafe) var flagsChangedMonitor: Any?
    var currentModifierFlags: NSEvent.ModifierFlags = []
    var shouldResetSelectionToFirstDisplayedItem = false
    var hasPreparedPanelData = false
    var isPanelPresentationActive = false
    var needsReloadOnNextPresentation = false
    var dataLoadGeneration: UInt = 0
    var itemIndexByID: [UUID: Int] = [:]
    var itemIndexByHash: [String: Int] = [:]
    let settingsViewModel: SettingsViewModel

    init(
        clipboardMonitor _: ClipboardMonitor? = nil,
        settingsViewModel: SettingsViewModel? = nil
    ) {
        self.settingsViewModel = settingsViewModel ?? SettingsViewModel.shared
        ModifierKey.migrateStoredPreferences()

        self.groups = [
            ClipboardGroup(id: UUID(), name: "链接", iconName: "link")
        ]

        setupDataSubscriptions()
        setupRecordChangeSubscriptions()
        setupFilterPipeline()
        setupGroupSwitchSubscriptions()
        setupSmartGroupsGuard()
        setupModifierPreferenceSync()
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
        }
    }
}
