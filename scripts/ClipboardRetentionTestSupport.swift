import Foundation
import SwiftData

// Minimal collaborators for compiling the production record and cleanup extension.
enum ClipboardContentType: String {
    case text, code, image
}

extension Notification.Name {
    static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
}

@ModelActor
actor ClipboardStoreActor {
    func markSyncAnchorUpdated() throws { }

    func seed(cutoff: Date) throws {
        let old = cutoff.addingTimeInterval(-1)
        let records = [
            ClipboardRecord(timestamp: old, contentHash: "top-pinned", typeRawValue: "text", topPinOrder: 100),
            ClipboardRecord(timestamp: old, contentHash: "expired", typeRawValue: "text"),
            ClipboardRecord(timestamp: cutoff, contentHash: "boundary", typeRawValue: "text"),
            ClipboardRecord(timestamp: cutoff.addingTimeInterval(1), contentHash: "recent", typeRawValue: "text"),
            ClipboardRecord(timestamp: old, contentHash: "favorite", typeRawValue: "image", isPinned: true),
            ClipboardRecord(timestamp: old, contentHash: "legacy-group", typeRawValue: "image", groupId: "custom"),
            ClipboardRecord(timestamp: old, contentHash: "multi-group", typeRawValue: "text", groupIdsRaw: "[\"a\",\"b\"]"),
            ClipboardRecord(timestamp: old, contentHash: "imported", typeRawValue: "text", groupId: "paste-board",
                            groupIdsRaw: "[\"paste-board\"]"),
            ClipboardRecord(timestamp: old, contentHash: "empty-groups", typeRawValue: "text", groupId: "",
                            groupIdsRaw: "[\"\"]"),
            ClipboardRecord(timestamp: old, contentHash: "empty-array", typeRawValue: "text", groupIdsRaw: "[]"),
            ClipboardRecord(timestamp: old, contentHash: "legacy-invalid-json", typeRawValue: "text", groupId: "custom",
                            groupIdsRaw: "invalid")
        ]
        for record in records { modelContext.insert(record) }
        try modelContext.save()
    }

    func hashes() throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<ClipboardRecord>()).map(\.contentHash))
    }

    func removeGroupMemberships(hash: String) throws {
        let records = try modelContext.fetch(FetchDescriptor<ClipboardRecord>())
        for record in records where record.contentHash == hash {
            record.groupId = nil
            record.groupIdsRaw = nil
        }
        try modelContext.save()
    }
}
