import SwiftUI

struct ClipboardMainView: View {
    enum PendingListFocusRequest {
        case preserveSelection
        case selectFirstItem
    }

    @Environment(ClipboardRuntimeStore.self) var runtimeStore
    @Environment(ScreenPinViewModel.self) var screenPinViewModel
    @Environment(\.openSettings) var openSettings
    @State var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage(PreviewPanelMode.defaultsKey) var previewPanelMode: PreviewPanelMode = .disabled
    @AppStorage("appTheme") var appTheme: AppTheme = .system
    @FocusState var focusedField: ClipboardPanelFocusField?

    var focusedFieldState: FocusState<ClipboardPanelFocusField?> {
        _focusedField
    }

    @State var isPanelKeyWindow = false
    @State var pendingListFocusRequest: PendingListFocusRequest?
    @State var pendingListFocusGeneration: UInt = 0
    @State var pendingSearchFocusGeneration: UInt = 0
    @State var pendingBlindTypedSearchText = ""
    @State var pendingBlindTypedBaseSearchText: String?
    @State var pendingBlindTypedSearchEvents: [NSEvent] = []
    let searchService = TypeToSearchService.shared

    var body: some View {
        configuredContent
    }

    @ViewBuilder
    var panelLayoutContent: some View {
        Group {
            if clipboardLayout == .horizontal {
                VStack(spacing: 0) {
                    ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    mainContent
                }
            } else {
                VStack(spacing: 0) {
                    ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    mainContent
                    historyPreviewFooter
                }
            }
        }
    }

    var configuredContent: some View {
        panelLayoutContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
            .background(
                ClipboardPanelWindowObserver(
                    onWindowDidBecomeKey: handlePanelDidBecomeKey,
                    onWindowDidResignKey: handlePanelDidResignKey
                )
            )
            .background(WindowAppearanceObserver(theme: appTheme))
            .overlay(alignment: .top) {
                if let operationNotice = currentOperationNotice {
                    ClipboardOperationNoticeView(message: operationNotice)
                        .padding(.top, (clipboardLayout == .vertical || clipboardLayout == .compact) ? 72 : 52)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: (clipboardLayout == .vertical || clipboardLayout == .compact) ? 14 : 0))
            .ignoresSafeArea()
            .animation(.spring(response: 0.24, dampingFraction: 0.9), value: currentOperationNotice != nil)
            .onChange(of: clipboardLayout) {
                // Only resize the AppKit panel after the AppStorage-backed SwiftUI layout
                // has already switched, avoiding a one-frame stretch of the old content.
                NotificationCenter.default.post(
                    name: .clipboardLayoutModeChanged,
                    object: clipboardLayout
                )
                requestDefaultListFocus()
            }
            .onChange(of: previewPanelMode) {
                NotificationCenter.default.post(
                    name: .clipboardPreviewPanelChanged,
                    object: previewPanelMode
                )
            }
            .onChange(of: focusedField) { _, newValue in
                viewModel.panelFocusField = newValue

                guard newValue == .searchBar else {
                    searchService.isTextFieldFocused = false
                    return
                }

                DispatchQueue.main.async {
                    searchService.isTextFieldFocused = isActiveTextInputResponder
                }
            }
            .onChange(of: displayedItemIDs) { _, _ in
                if applyPendingListFocusIfPossible() {
                    return
                }

                if focusedField == .clipList {
                    viewModel.ensureListSelection()
                }
            }
            .onChange(of: viewModel.searchInput) { oldValue, newValue in
                guard !oldValue.isEmpty, newValue.isEmpty else { return }
                requestListFocusAfterSearchExit()
            }
            .onAppear {
                searchService.onInterceptedKey = { [weak viewModel] event in
                    guard let viewModel else { return false }

                    guard viewModel.shouldStartTypeToSearch(with: event),
                          let acceptedInput = viewModel.acceptedSearchInput(from: event) else {
                        return false
                    }

                    bufferBlindTypedSearchInput(acceptedInput, event: event)
                    focusSearchField(collapseSelectionToInsertionPoint: true)
                    return true
                }
                requestDefaultListFocus()
            }
            .onDisappear {
                searchService.onInterceptedKey = nil
                deactivatePanelInputHandling()
            }
            // ── ⌘, 意图通知 → 调用 SwiftUI 原生 openSettings ───────────
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsIntent)) { _ in
                SettingsWindowCoordinator.open {
                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearchFieldIntent)) { _ in
                requestSearchFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusListIntent)) { _ in
                requestListFocusPreservingSelection()
            }
            .sheet(item: titleEditorItemBinding, onDismiss: viewModel.dismissTitleEditor) { item in
                ClipboardItemTitleEditorSheet(item: item) { title in
                    viewModel.saveCustomTitle(for: item, title: title)
                }
            }
    }

}

#Preview {
    ClipboardMainView()
        .environmentObject(AppPreferencesStore.shared)
        .environment(ClipboardRuntimeStore.shared)
}
