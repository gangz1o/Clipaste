import SwiftUI


extension ClipboardMainView {
    var titleEditorItemBinding: Binding<ClipboardItem?> {
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
    func applyPendingListFocusIfPossible() -> Bool {
        guard let pendingListFocusRequest else { return false }
        guard isPanelKeyWindow else { return false }
        guard !displayedItems.isEmpty else { return false }

        switch pendingListFocusRequest {
        case .preserveSelection:
            viewModel.ensureListSelection()
        case .selectFirstItem:
            viewModel.selectFirstDisplayedItem()
        }
        focusedField = .clipList
        self.pendingListFocusRequest = nil
        return true
    }

    func applySearchFieldFocusIfPossible(
        generation: UInt,
        remainingAttempts: Int,
        collapseSelectionToInsertionPoint: Bool
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
                replayPendingBlindTypedSearchEventsIfNeeded()

                DispatchQueue.main.async {
                    finalizePendingBlindTypedSearchInputIfNeeded()
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
                    collapseSelectionToInsertionPoint: collapseSelectionToInsertionPoint
                )
            }
        }
    }

    func bufferBlindTypedSearchInput(_ input: String, event: NSEvent) {
        if pendingBlindTypedBaseSearchText == nil {
            pendingBlindTypedBaseSearchText = viewModel.searchInput
        }

        pendingBlindTypedSearchText.append(input)
        pendingBlindTypedSearchEvents.append(event)
    }

    func replayPendingBlindTypedSearchEventsIfNeeded() {
        guard let textView = activeTextInputView else { return }
        guard !pendingBlindTypedSearchEvents.isEmpty else { return }

        let pendingEvents = pendingBlindTypedSearchEvents
        pendingBlindTypedSearchEvents.removeAll()
        textView.interpretKeyEvents(pendingEvents)
    }

    func finalizePendingBlindTypedSearchInputIfNeeded() {
        guard let baseSearchText = pendingBlindTypedBaseSearchText else { return }
        guard !pendingBlindTypedSearchText.isEmpty else {
            pendingBlindTypedBaseSearchText = nil
            return
        }

        if let textView = activeTextInputView, textView.hasMarkedText() {
            resetPendingBlindTypedSearchInput()
            return
        }

        let expectedSearchText = baseSearchText + pendingBlindTypedSearchText
        let currentSearchText = viewModel.searchInput

        if currentSearchText == expectedSearchText || currentSearchText != baseSearchText {
            resetPendingBlindTypedSearchInput()
            return
        }

        viewModel.searchInput = expectedSearchText
        resetPendingBlindTypedSearchInput()
    }

    func resetPendingBlindTypedSearchInput() {
        pendingBlindTypedSearchText = ""
        pendingBlindTypedBaseSearchText = nil
        pendingBlindTypedSearchEvents.removeAll()
    }

    func collapseActiveTextSelectionToInsertionPoint() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return
        }

        guard !textView.hasMarkedText() else {
            return
        }

        let stringLength = textView.string.count
        textView.setSelectedRange(NSRange(location: stringLength, length: 0))
    }

    var isActiveTextInputResponder: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }

        return responder is NSTextView || responder is NSTextField
    }

    var activeTextInputView: NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            return textView
        }

        if let textField = NSApp.keyWindow?.firstResponder as? NSTextField,
           let fieldEditor = textField.window?.fieldEditor(true, for: textField) as? NSTextView {
            return fieldEditor
        }

        return nil
    }

}
