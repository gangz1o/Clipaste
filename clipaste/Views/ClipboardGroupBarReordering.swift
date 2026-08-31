import SwiftUI
import UniformTypeIdentifiers


enum GroupInsertEdge {
    case leading
    case trailing
}

struct GroupReorderTarget: Equatable {
    let groupID: String
    let edge: GroupInsertEdge
}

enum GroupBarDropSpace {
    static let name = "ClipboardHeader.GroupBarDropSpace"
}

struct GroupTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct GroupBarDropDelegate: DropDelegate {
    let orderedGroupIDs: [String]
    let groupFrames: [String: CGRect]
    @Binding var reorderTarget: GroupReorderTarget?
    let viewModel: ClipboardViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [ClipboardDragType.group])
    }

    func dropEntered(info: DropInfo) {
        updateReorderPosition(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateReorderPosition(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard reorderTarget != nil else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            reorderTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.12)) {
            reorderTarget = nil
        }
        viewModel.draggedGroup = nil
        viewModel.saveGroupOrder()
        return true
    }

    private func updateReorderPosition(info: DropInfo) {
        guard let draggedGroup = viewModel.draggedGroup,
              let nextTarget = resolvedReorderTarget(at: info.location),
              draggedGroup.id != nextTarget.groupID else { return }

        if reorderTarget != nextTarget {
            withAnimation(.easeInOut(duration: 0.12)) {
                reorderTarget = nextTarget
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.moveGroup(
                from: draggedGroup.id,
                relativeTo: nextTarget.groupID,
                insertAfter: nextTarget.edge == .trailing
            )
        }
    }

    private func resolvedReorderTarget(at location: CGPoint) -> GroupReorderTarget? {
        guard let first = orderedFrames.first,
              let last = orderedFrames.last else { return nil }

        if location.x <= first.frame.midX {
            return GroupReorderTarget(groupID: first.id, edge: .leading)
        }

        for entry in orderedFrames {
            if location.x <= entry.frame.maxX {
                let edge: GroupInsertEdge = location.x <= entry.frame.midX ? .leading : .trailing
                return GroupReorderTarget(groupID: entry.id, edge: edge)
            }
        }

        return GroupReorderTarget(groupID: last.id, edge: .trailing)
    }

    private var orderedFrames: [(id: String, frame: CGRect)] {
        orderedGroupIDs.compactMap { id in
            guard let frame = groupFrames[id] else { return nil }
            return (id, frame)
        }
    }
}

// MARK: - Window Drag Handle
