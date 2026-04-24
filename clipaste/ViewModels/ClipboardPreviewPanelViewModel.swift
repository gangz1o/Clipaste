import Observation
import SwiftUI

@Observable
@MainActor
final class ClipboardPreviewPanelViewModel {
    private enum Constants {
        static let hoverDelay: Duration = .milliseconds(80)
    }

    private(set) var selectedItem: ClipboardItem?
    private(set) var keyboardSelectedItem: ClipboardItem?
    private(set) var isHoveringItem = false

    @ObservationIgnored
    private var hoverTask: Task<Void, Never>?

    deinit {
        hoverTask?.cancel()
    }

    func handleHoverChange(
        for item: ClipboardItem,
        isHovering: Bool,
        items: [ClipboardItem],
        selectedItemIDs: Set<UUID>,
        isPreviewEnabled: Bool
    ) {
        guard isPreviewEnabled else { return }

        hoverTask?.cancel()

        if isHovering {
            isHoveringItem = true
            hoverTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: Constants.hoverDelay)
                guard Task.isCancelled == false else { return }
                self.updatePreview(to: item)
            }
        } else {
            isHoveringItem = false
            updatePreviewFromKeyboardSelection(
                items: items,
                selectedItemIDs: selectedItemIDs,
                animated: false
            )
        }
    }

    func handleSelectionChange(
        items: [ClipboardItem],
        selectedItemIDs: Set<UUID>,
        isPreviewEnabled: Bool
    ) {
        guard isPreviewEnabled else {
            clear()
            return
        }

        keyboardSelectedItem = selectedItem(in: items, selectedItemIDs: selectedItemIDs)

        guard isHoveringItem == false else { return }

        updatePreviewFromKeyboardSelection(
            items: items,
            selectedItemIDs: selectedItemIDs
        )
    }

    func reconcile(
        items: [ClipboardItem],
        selectedItemIDs: Set<UUID>,
        isPreviewEnabled: Bool
    ) {
        guard isPreviewEnabled else {
            clear()
            return
        }

        if let selectedItem,
           let refreshedItem = items.first(where: { $0.id == selectedItem.id }) {
            self.selectedItem = refreshedItem
        }

        keyboardSelectedItem = selectedItem(in: items, selectedItemIDs: selectedItemIDs)

        if selectedItem == nil {
            updatePreviewFromKeyboardSelection(
                items: items,
                selectedItemIDs: selectedItemIDs,
                animated: false
            )
        } else if items.contains(where: { $0.id == selectedItem?.id }) == false {
            updatePreviewFromKeyboardSelection(
                items: items,
                selectedItemIDs: selectedItemIDs,
                animated: false
            )
        }
    }

    func handlePreviewModeChange(
        items: [ClipboardItem],
        selectedItemIDs: Set<UUID>,
        isPreviewEnabled: Bool
    ) {
        guard isPreviewEnabled else {
            clear()
            return
        }

        keyboardSelectedItem = selectedItem(in: items, selectedItemIDs: selectedItemIDs)
        updatePreviewFromKeyboardSelection(
            items: items,
            selectedItemIDs: selectedItemIDs,
            animated: false
        )
    }

    private func updatePreviewFromKeyboardSelection(
        items: [ClipboardItem],
        selectedItemIDs: Set<UUID>,
        animated: Bool = true
    ) {
        if let keyboardSelectedItem {
            updatePreview(to: keyboardSelectedItem, animated: animated)
            return
        }

        guard let fallbackItem = selectedItem(in: items, selectedItemIDs: selectedItemIDs) else {
            selectedItem = nil
            return
        }

        keyboardSelectedItem = fallbackItem
        updatePreview(to: fallbackItem, animated: animated)
    }

    private func selectedItem(
        in items: [ClipboardItem],
        selectedItemIDs: Set<UUID>
    ) -> ClipboardItem? {
        guard let selectedID = selectedItemIDs.first else { return nil }
        return items.first(where: { $0.id == selectedID })
    }

    private func updatePreview(
        to item: ClipboardItem,
        animated: Bool = true
    ) {
        guard selectedItem != item else { return }

        if animated {
            withAnimation {
                selectedItem = item
            }
        } else {
            selectedItem = item
        }
    }

    private func clear() {
        hoverTask?.cancel()
        hoverTask = nil
        isHoveringItem = false
        keyboardSelectedItem = nil
        selectedItem = nil
    }
}
