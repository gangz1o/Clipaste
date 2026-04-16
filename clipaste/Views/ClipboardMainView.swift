import SwiftUI

struct ClipboardMainView: View {
    private enum PendingListFocusRequest {
        case selectFirstItem
    }

    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @Environment(\.openSettings) private var openSettings
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @FocusState private var focusedField: ClipboardPanelFocusField?

    @State private var isPanelKeyWindow = false
    @State private var pendingListFocusRequest: PendingListFocusRequest?
    @State private var pendingListFocusGeneration: UInt = 0
    @State private var pendingSearchFocusGeneration: UInt = 0
    private let searchService = TypeToSearchService.shared

    var body: some View {
        configuredContent
    }

    @ViewBuilder
    private var panelLayoutContent: some View {
        Group {
            if clipboardLayout == .horizontal {
                VStack(spacing: 0) {
                    ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    mainContent
                }
            } else {
                mainContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        historyPreviewFooter
                    }
            }
        }
    }

    private var configuredContent: some View {
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
                if let operationNotice = viewModel.operationNotice {
                    ClipboardOperationNoticeView(message: operationNotice)
                        .padding(.top, (clipboardLayout == .vertical || clipboardLayout == .compact) ? 72 : 52)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: (clipboardLayout == .vertical || clipboardLayout == .compact) ? 14 : 0))
            .preferredColorScheme(appTheme.colorScheme)
            .ignoresSafeArea()
            .animation(.spring(response: 0.24, dampingFraction: 0.9), value: viewModel.operationNotice != nil)
            .onChange(of: clipboardLayout) {
                // Only resize the AppKit panel after the AppStorage-backed SwiftUI layout
                // has already switched, avoiding a one-frame stretch of the old content.
                NotificationCenter.default.post(
                    name: .clipboardLayoutModeChanged,
                    object: clipboardLayout
                )
                requestDefaultListFocus()
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

                    let shouldEnterSearch = viewModel.shouldStartTypeToSearch(with: event)
                    if shouldEnterSearch {
                        focusSearchField(
                            interceptedEvent: event,
                            collapseSelectionToInsertionPoint: true
                        )
                    }

                    return shouldEnterSearch
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

    @ViewBuilder
    private var mainContent: some View {
        if displayedItems.isEmpty {
            ClipboardEmptyStateView(viewModel: viewModel)
        } else {
            switch clipboardLayout {
            case .horizontal:
                ClipboardHorizontalView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: _focusedField
                )
            case .vertical, .compact:
                ClipboardVerticalListView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: _focusedField
                )
            }
        }
    }

    private func focusSearchField(
        interceptedEvent: NSEvent? = nil,
        collapseSelectionToInsertionPoint: Bool = false
    ) {
        pendingListFocusGeneration &+= 1
        pendingListFocusRequest = nil
        pendingSearchFocusGeneration &+= 1
        let generation = pendingSearchFocusGeneration

        focusedField = nil
        searchService.isTextFieldFocused = false

        DispatchQueue.main.async {
            applySearchFieldFocusIfPossible(
                generation: generation,
                remainingAttempts: 3,
                collapseSelectionToInsertionPoint: collapseSelectionToInsertionPoint,
                interceptedEvent: interceptedEvent
            )
        }
    }

    private func requestSearchFocus() {
        focusSearchField()
    }

    private func requestListFocusPreservingSelection() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = nil
        focusedField = .clipList
        searchService.isTextFieldFocused = false
        viewModel.ensureListSelection()
    }

    private func activatePanelInputHandling() {
        isPanelKeyWindow = true
        viewModel.beginPresentation()
        viewModel.startKeyboardMonitoring()
        // 先启动面板级键盘监听，再启动盲打搜索，确保特殊按键优先被 ViewModel 消费。
        searchService.start()
        requestDefaultListFocus()
    }

    private func deactivatePanelInputHandling() {
        isPanelKeyWindow = false
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = nil
        searchService.stop()
        viewModel.stopKeyboardMonitoring()
        viewModel.endPresentation()
    }

    private func handlePanelDidBecomeKey() {
        activatePanelInputHandling()
    }

    private func handlePanelDidResignKey() {
        deactivatePanelInputHandling()
    }

    private func requestDefaultListFocus() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = .selectFirstItem
        focusedField = nil
        searchService.isTextFieldFocused = false

        DispatchQueue.main.async {
            _ = applyPendingListFocusIfPossible()
        }
    }

    private func requestListFocusAfterSearchExit() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        let generation = pendingListFocusGeneration

        pendingListFocusRequest = .selectFirstItem
        focusedField = nil
        searchService.isTextFieldFocused = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard pendingListFocusGeneration == generation else { return }
            _ = applyPendingListFocusIfPossible()
        }
    }

    private var titleEditorItemBinding: Binding<ClipboardItem?> {
        Binding(
            get: { viewModel.titleEditorItem },
            set: { newValue in
                if let newValue {
                    viewModel.titleEditorItem = newValue
                } else {
                    viewModel.dismissTitleEditor()
                }
            }
        )
    }

    @discardableResult
    private func applyPendingListFocusIfPossible() -> Bool {
        guard pendingListFocusRequest != nil else { return false }
        guard isPanelKeyWindow else { return false }
        guard !displayedItems.isEmpty else { return false }

        viewModel.selectFirstDisplayedItem()
        focusedField = .clipList
        pendingListFocusRequest = nil
        return true
    }

    private func applySearchFieldFocusIfPossible(
        generation: UInt,
        remainingAttempts: Int,
        collapseSelectionToInsertionPoint: Bool,
        interceptedEvent: NSEvent?
    ) {
        guard pendingSearchFocusGeneration == generation else { return }
        guard isPanelKeyWindow else { return }

        focusedField = .searchBar

        DispatchQueue.main.async {
            guard pendingSearchFocusGeneration == generation else { return }
            guard isPanelKeyWindow else { return }

            if isActiveTextInputResponder {
                if collapseSelectionToInsertionPoint {
                    collapseActiveTextSelectionToInsertionPoint()
                }
                searchService.isTextFieldFocused = true
                if let interceptedEvent {
                    replayInterceptedSearchEvent(interceptedEvent)
                }
                return
            }

            guard remainingAttempts > 0 else { return }

            focusedField = nil
            searchService.isTextFieldFocused = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                applySearchFieldFocusIfPossible(
                    generation: generation,
                    remainingAttempts: remainingAttempts - 1,
                    collapseSelectionToInsertionPoint: collapseSelectionToInsertionPoint,
                    interceptedEvent: interceptedEvent
                )
            }
        }
    }

    private func collapseActiveTextSelectionToInsertionPoint() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return
        }

        guard !textView.hasMarkedText() else {
            return
        }

        let stringLength = textView.string.count
        textView.setSelectedRange(NSRange(location: stringLength, length: 0))
    }

    private func replayInterceptedSearchEvent(_ event: NSEvent) {
        guard let textView = activeTextInputView else {
            return
        }

        textView.interpretKeyEvents([event])
    }

    private var isActiveTextInputResponder: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }

        return responder is NSTextView || responder is NSTextField
    }

    private var activeTextInputView: NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            return textView
        }

        if let textField = NSApp.keyWindow?.firstResponder as? NSTextField,
           let fieldEditor = textField.window?.fieldEditor(true, for: textField) as? NSTextView {
            return fieldEditor
        }

        return nil
    }

    private var displayedItems: [ClipboardItem] {
        viewModel.displayedItems
    }

    private var displayedItemIDs: [UUID] {
        viewModel.displayedItemIDs
    }

    @ViewBuilder
    private var historyPreviewFooter: some View {
        HStack {
            Spacer()

            Text("\(displayedItems.count) Items")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .padding(.top, 4)
        .background(.regularMaterial)
    }
}

#Preview {
    ClipboardMainView()
        .environmentObject(AppPreferencesStore.shared)
        .environmentObject(ClipboardRuntimeStore.shared)
}
