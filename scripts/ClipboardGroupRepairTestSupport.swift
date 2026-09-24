import Foundation
import SwiftData

// Minimal collaborators for compiling the production group model and repair extension.
enum IconType {
    case system, custom
}

@MainActor
enum IconPickerViewModel {
    static let customIconNames: Set<String> = []
}

@ModelActor
actor ClipboardStoreActor {
    func markSyncAnchorUpdated() throws { }

    func seed() throws {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let groups = [
            ClipboardGroupModel(id: "live", name: "Live"),
            ClipboardGroupModel(id: "live-dup", name: "Code", sortOrder: 1),
            ClipboardGroupModel(id: "live-dup", name: "Code", sortOrder: 1),
            ClipboardGroupModel(id: "tombstone-dup", name: "Dev", deletedAt: early, deletedByDevice: "A"),
            ClipboardGroupModel(id: "tombstone-dup", name: "Dev", deletedAt: late, deletedByDevice: "B"),
            ClipboardGroupModel(id: "mixed", name: "3D"),
            ClipboardGroupModel(id: "mixed", name: "3D", deletedAt: early, deletedByDevice: "A"),
            ClipboardGroupModel(id: "tombstone", name: "Old", deletedAt: early)
        ]
        for group in groups { modelContext.insert(group) }
        try modelContext.save()
    }

    func rows() throws -> [(id: String, deletedAt: Date?, deletedByDevice: String)] {
        try modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())
            .map { ($0.id, $0.deletedAt, $0.deletedByDevice) }
    }

    func activeItems() throws -> [ClipboardGroupItem] {
        try modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())
            .filter { $0.deletedAt == nil }
            .map { ClipboardGroupItem(id: $0.id, name: $0.name, systemIconName: nil, sortOrder: $0.sortOrder) }
            .uniquedByID()
    }
}
