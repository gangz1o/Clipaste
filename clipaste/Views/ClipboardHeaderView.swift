import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHeaderView: View {
    enum HorizontalSearchLayout {
        static let fieldHeight: CGFloat = 28
        static let collapsedWidth: CGFloat = fieldHeight
        static let expandedWidth: CGFloat = 240
        static let horizontalPadding: CGFloat = 12
        static let contentSpacing: CGFloat = 8
    }

    var viewModel: ClipboardViewModel
    @Environment(\.openSettings) var openSettings
    @EnvironmentObject var preferencesStore: AppPreferencesStore
    @FocusState var focusedField: ClipboardPanelFocusField?
    @AppStorage("clipboardLayout") var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .auto
    @AppStorage("appAccentColor") var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("isPanelPinned") var isPanelPinned: Bool = false
    @AppStorage("isMonitoringPaused") var isMonitoringPaused: Bool = false
    @AppStorage("monitorInterval") var monitorInterval: Double = 0.5
    @State var isShowingNewGroupPopover = false
    @StateObject var newGroupEditor = GroupEditorViewModel(mode: .create)
    @State var targetedGroupId: String? = nil
    @State var targetedBuiltInGroup: ClipboardBuiltInGroup? = nil
    @State var groupTabFrames: [String: CGRect] = [:]
    @State var reorderTarget: GroupReorderTarget? = nil
    @State var isShowingGroupOverflowPopover = false
    @State var isShowingAIModelPopover = false
    @State var isAIModelSubmenuHovered = false
    @State var aiSettingsViewModel = AISettingsViewModel.shared

    // MARK: - 重命名 / 删除分组弹窗控制
    @State var groupToEdit: ClipboardGroupItem? = nil
    @StateObject var editGroupEditor = GroupEditorViewModel(mode: .edit)
    @State var showEditPopover = false
    @State var groupToDelete: ClipboardGroupItem? = nil
    @State var showDeleteAlert = false

    /// 剪贴板面板上的 Popover 在独立窗口中呈现，往往拿不到根视图的 `\.locale`，需与 `ClipboardPanelRootView` 一致显式注入。
    var panelLocale: Locale {
        appLanguage.resolvedLocale
    }

    var isVerticalLayout: Bool {
        clipboardLayout == .vertical || clipboardLayout == .compact
    }

    var groupBarSpacing: CGFloat {
        isVerticalLayout ? 2 : 4
    }

    var groupTabHorizontalPadding: CGFloat {
        isVerticalLayout ? 9 : 12
    }

    var groupTabVerticalPadding: CGFloat {
        isVerticalLayout ? 4 : 5
    }

    var groupTabIconSpacing: CGFloat {
        isVerticalLayout ? 4 : 5
    }

    var body: some View {
        Group {
            if isVerticalLayout {
                verticalHeader
            } else {
                horizontalHeader
            }
        }
        .padding(.bottom, isCompactMode ? 4 : 8)
        .background(headerBackground)
        .popover(isPresented: $showEditPopover, arrowEdge: .bottom) {
            editGroupPopover
                .environment(\.locale, panelLocale)
        }
        .onChange(of: isShowingNewGroupPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing)
        }
        .onChange(of: showEditPopover) { _, isShowing in
            updatePopoverInputState(isShowing: isShowing)
            if isShowing == false {
                groupToEdit = nil
            }
        }
        .onAppear {
            preferencesStore.refreshLaunchAtLoginStatus()
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
        .onChange(of: showDeleteAlert) { _, isShowing in
            ClipboardPanelManager.shared.suppressHide = isShowing
        }
    }

    @ViewBuilder
    var headerBackground: some View {
        if isVerticalLayout {
            WindowDragArea()
                .background(.regularMaterial)
        } else {
            Color.clear
        }
    }

    // MARK: - 竖版模式：双行布局
}

#Preview {
    ClipboardHeaderPreview()
}
