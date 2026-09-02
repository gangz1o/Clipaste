import SwiftUI


extension ClipboardMainView {
    var currentOperationNotice: String? {
        screenPinViewModel.operationNotice ?? viewModel.operationNotice
    }

    @ViewBuilder
    var mainContent: some View {
        if displayedItems.isEmpty {
            ClipboardEmptyStateView(viewModel: viewModel)
        } else {
            switch clipboardLayout {
            case .horizontal:
                ClipboardHorizontalView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: focusedFieldState
                )
            case .vertical, .compact:
                ClipboardVerticalListView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: focusedFieldState
                )
            }
        }
    }

    func focusSearchField(collapseSelectionToInsertionPoint: Bool = false) {
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
                collapseSelectionToInsertionPoint: collapseSelectionToInsertionPoint
            )
        }
    }

    func requestSearchFocus() {
        focusSearchField()
    }

    func requestListFocusPreservingSelection() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = nil
        focusedField = .clipList
        searchService.isTextFieldFocused = false
        resetPendingBlindTypedSearchInput()
        viewModel.ensureListSelection()
    }

    func activatePanelInputHandling() {
        isPanelKeyWindow = true
        viewModel.beginPresentation()
        viewModel.startKeyboardMonitoring()
        // 先启动面板级键盘监听，再启动盲打搜索，确保特殊按键优先被 ViewModel 消费。
        searchService.start()
        requestDefaultListFocus()
    }

    func deactivatePanelInputHandling() {
        isPanelKeyWindow = false
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = nil
        resetPendingBlindTypedSearchInput()
        searchService.stop()
        viewModel.stopKeyboardMonitoring()
        viewModel.endPresentation()
    }

    func handlePanelDidBecomeKey() {
        activatePanelInputHandling()
    }

    func handlePanelDidResignKey() {
        deactivatePanelInputHandling()
    }

    func requestDefaultListFocus() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        pendingListFocusRequest = viewModel.settingsViewModel.autoFocusFirstItemOnPanelActivation
            ? .selectFirstItem
            : .preserveSelection
        let generation = pendingListFocusGeneration
        focusedField = nil
        searchService.isTextFieldFocused = false
        resetPendingBlindTypedSearchInput()

        DispatchQueue.main.async {
            applyPendingListFocusWhenReady(generation: generation, remainingAttempts: 12)
        }
    }

    func requestListFocusAfterSearchExit() {
        pendingListFocusGeneration &+= 1
        pendingSearchFocusGeneration &+= 1
        let generation = pendingListFocusGeneration

        pendingListFocusRequest = .selectFirstItem
        focusedField = nil
        searchService.isTextFieldFocused = false
        resetPendingBlindTypedSearchInput()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard pendingListFocusGeneration == generation else { return }
            _ = applyPendingListFocusIfPossible()
        }
    }

}
