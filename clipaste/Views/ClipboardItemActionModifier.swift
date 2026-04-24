import SwiftUI

// MARK: - Single-click select / paste modifier

struct ClipboardItemActionModifier: ViewModifier {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    func body(content: Content) -> some View {
        content
            // Ensure transparent areas are also tappable
            .contentShape(Rectangle())
            // Keep primary activation immediate: a single click selects the item and
            // performs the existing paste-to-active-app action.
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.handlePrimaryClickSelection(for: item.id)
                viewModel.pasteToActiveApp(item: item)
            })
    }
}

extension View {
    /// Attach single-click select + paste behaviour to any clipboard card.
    func clipboardItemActions(for item: ClipboardItem, viewModel: ClipboardViewModel) -> some View {
        self.modifier(ClipboardItemActionModifier(item: item, viewModel: viewModel))
    }
}

// MARK: - Optional-ViewModel variant for ClipboardCardView

/// Handles ClipboardCardView which has an optional viewModel and a legacy onSelect callback.
struct ClipboardCardActionModifier: ViewModifier {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.handlePrimaryClickSelection(for: item.id)
                viewModel.pasteToActiveApp(item: item)
            })
    }
}
