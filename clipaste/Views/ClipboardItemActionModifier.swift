import SwiftUI

// MARK: - Single-click select / Double-click paste modifier

struct ClipboardItemActionModifier: ViewModifier {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    func body(content: Content) -> some View {
        content
            // Ensure transparent areas are also tappable
            .contentShape(Rectangle())
            // Make selection feel instant. Double-click still fires paste, but single-click
            // no longer waits for the double-click recognition window to expire.
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.userDidSelect(item: item)
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                viewModel.pasteToActiveApp(item: item)
            })
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
            .simultaneousGesture(TapGesture().onEnded {
                if let vm = viewModel {
                    vm.userDidSelect(item: item)
                } else {
                    onSelect()
                }
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if let vm = viewModel {
                    vm.pasteToActiveApp(item: item)
                } else {
                    onSelect()
                }
            })
    }
}
