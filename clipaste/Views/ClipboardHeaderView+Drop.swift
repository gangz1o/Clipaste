import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    func handleItemDrop(
        providers: [NSItemProvider],
        onResolvedItem: @escaping @MainActor @Sendable (ClipboardItem) -> Void
    ) -> Bool {
        if let draggedItemId = viewModel.draggedItemId,
           let draggedItem = viewModel.items.first(where: { $0.id == draggedItemId }) {
            onResolvedItem(draggedItem)
            viewModel.draggedItemId = nil
            return true
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(ClipboardDragType.item) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: ClipboardDragType.item) { data, _ in
            if let data,
               let idString = String(data: data, encoding: .utf8),
               let uuid = UUID(uuidString: idString) {
                DispatchQueue.main.async {
                    if let draggedItem = viewModel.items.first(where: { $0.id == uuid }) {
                        onResolvedItem(draggedItem)
                        viewModel.draggedItemId = nil
                    }
                }
            }
        }
        return true
    }
}
