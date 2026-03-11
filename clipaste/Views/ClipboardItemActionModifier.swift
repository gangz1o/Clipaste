import SwiftUI

// MARK: - Single-click select / Double-click paste modifier

struct ClipboardItemActionModifier: ViewModifier {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    func body(content: Content) -> some View {
        content
            // Ensure transparent areas are also tappable
            .contentShape(Rectangle())
            // Double-tap must come BEFORE single-tap, otherwise single-tap intercepts it
            .onTapGesture(count: 2) {
                viewModel.pasteToActiveApp(item: item)
            }
            .onTapGesture(count: 1) {
                viewModel.userDidSelect(item: item)
            }
    }
}

extension View {
    /// Attach single-click select + double-click paste behaviour to any clipboard card.
    func clipboardItemActions(for item: ClipboardItem, viewModel: ClipboardViewModel) -> some View {
        self.modifier(ClipboardItemActionModifier(item: item, viewModel: viewModel))
    }
}

// MARK: - Optional-ViewModel variant for ClipboardCardView

/// Handles ClipboardCardView which has an optional viewModel and a legacy onSelect callback.
struct ClipboardCardActionModifier: ViewModifier {
    let item: ClipboardItem
    let onSelect: () -> Void
    let viewModel: ClipboardViewModel?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Double-tap must come first
            .onTapGesture(count: 2) {
                if let vm = viewModel {
                    vm.pasteToActiveApp(item: item)
                } else {
                    onSelect()
                }
            }
            .onTapGesture(count: 1) {
                if let vm = viewModel {
                    vm.userDidSelect(item: item)
                } else {
                    onSelect()
                }
            }
    }
}
