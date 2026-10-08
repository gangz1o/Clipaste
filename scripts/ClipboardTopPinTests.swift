import Foundation
import SwiftData

// Use production persistence, search and presentation ordering with a minimal UI mapping.
struct ClipboardItem: Sendable {
    let id: UUID
    let contentHash: String
    let timestamp: Date
    let topPinOrder: Double
}

enum StorageManager {
    nonisolated static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        ClipboardItem(id: record.id, contentHash: record.contentHash,
                      timestamp: record.timestamp, topPinOrder: record.topPinOrder)
    }
}

enum ClipboardContentType: String { case text, code, image }

@ModelActor
actor ClipboardStoreActor {
    func markSyncAnchorUpdated() throws { }

    func seed() throws {
        for index in 0..<150 {
            modelContext.insert(ClipboardRecord(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                contentHash: "r\(index)", typeRawValue: "text", plainText: "match \(index)"
            ))
        }
        try modelContext.save()
    }
}

@main
enum ClipboardTopPinTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "test.store")
        do {
            let container = try makeContainer(url)
            let actor = ClipboardStoreActor(modelContainer: container)
            try await actor.seed()
            await actor.setTopPin(hash: "r0", order: 1000)
            await actor.setTopPin(hash: "r1", order: 2000)
            let searcher = ClipboardSearcher(modelContainer: container)
            let first = await searcher.searchAndMap(searchText: "", fetchLimit: 2)
            precondition(first.map(\.contentHash) == ["r1", "r0"], "Old pinned records must precede new history before paging")
            let next = await searcher.searchAndMap(searchText: "", fetchLimit: 2, offset: 2)
            precondition(next.map(\.contentHash) == ["r149", "r148"])
            let filtered = await searcher.searchAndMap(searchText: "match", fetchLimit: 3)
            precondition(filtered.map(\.contentHash) == ["r1", "r0", "r149"])
            precondition(Array((next + first).sorted(by: ClipboardItem.precedesInHistory).prefix(2)).map(\.contentHash) == ["r1", "r0"])
        }
        // Reopen the SQLite store to verify persistence, then unpin to restore chronological order.
        let reopened = try makeContainer(url)
        let searcher = ClipboardSearcher(modelContainer: reopened)
        let restored = await searcher.searchAndMap(searchText: "", fetchLimit: 2)
        precondition(restored.allSatisfy(\.isTopPinned))
        let actor = ClipboardStoreActor(modelContainer: reopened)
        await actor.setTopPin(hash: "r1", order: 0)
        let after = await searcher.searchAndMap(searchText: "", fetchLimit: 2)
        precondition(after.map(\.contentHash) == ["r0", "r149"])
        let unpinned = await searcher.searchAndMap(searchText: "match 1", fetchLimit: 150)
        precondition(unpinned.first(where: { $0.contentHash == "r1" })?.timestamp == Date(timeIntervalSince1970: 1),
                     "Pinning must not modify copy time")
        print("ClipboardTopPinTests passed")
    }

    static func makeContainer(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: ClipboardRecord.self,
                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }
}
