import Foundation
import SwiftData

// Use production persistence and scoped queries with a minimal UI mapping.
struct ClipboardItem: Sendable {
    let contentHash: String
}

enum StorageManager {
    nonisolated static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        ClipboardItem(contentHash: record.contentHash)
    }
}

enum ClipboardContentType: String { case text, code, image }

@main
enum ClipboardScopedFetchTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try ModelContainer(
            for: ClipboardRecord.self,
            configurations: ModelConfiguration(
                url: directory.appending(path: "test.store"),
                cloudKitDatabase: .none
            )
        )
        let groupID = UUID().uuidString
        let otherGroupID = UUID().uuidString
        try seed(container, groupID: groupID, otherGroupID: otherGroupID)

        let searcher = ClipboardSearcher(modelContainer: container)
        func hashes(
            _ query: String = "",
            group: String? = nil,
            type: String? = nil,
            favorites: Bool = false,
            limit: Int = 0
        ) async -> [String] {
            await searcher.fetchScoped(
                searchText: query,
                groupId: group,
                typeRawValue: type,
                favoritesOnly: favorites,
                fetchLimit: limit
            ).map(\.contentHash)
        }

        // Old group members far outside the 80-item history window must still be found.
        let group = await hashes(group: groupID)
        precondition(group == ["r10", "r5", "r3"], "group scope must match groupId and groupIdsRaw: \(group)")
        let other = await hashes(group: otherGroupID)
        precondition(other == ["r5"], "multi-group records must match every group they belong to: \(other)")
        let limited = await hashes(group: groupID, limit: 2)
        precondition(limited == ["r10", "r5"], "scoped fetch must keep history order under a limit")

        let groupSearch = await hashes("match 1", group: groupID)
        precondition(groupSearch == ["r10"], "search inside a group must apply both conditions: \(groupSearch)")
        let groupMiss = await hashes("match 149", group: groupID)
        precondition(groupMiss.isEmpty, "search inside a group must not leak other records")

        let favorites = await hashes(favorites: true)
        precondition(favorites == ["r2"], "favorites scope must match pinned records: \(favorites)")
        let favoriteSearch = await hashes("match 2", favorites: true)
        precondition(favoriteSearch == ["r2"])

        let images = await hashes(type: "image")
        precondition(images == ["r4"], "type scope must match typeRawValue: \(images)")
        let imageMiss = await hashes("match 1", type: "image")
        precondition(imageMiss.isEmpty)

        let unscoped = await hashes()
        precondition(unscoped.isEmpty, "a fetch without any scope must not return the whole history")

        print("ClipboardScopedFetchTests passed")
    }

    private static func seed(_ container: ModelContainer, groupID: String, otherGroupID: String) throws {
        let context = ModelContext(container)
        for index in 0..<150 {
            let record = ClipboardRecord(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                contentHash: "r\(index)",
                typeRawValue: index == 4 ? "image" : "text",
                plainText: "match \(index)"
            )
            switch index {
            case 3:
                record.groupId = groupID
            case 5:
                record.groupIdsRaw = encodedGroupIDs([otherGroupID, groupID])
            case 10:
                record.groupId = groupID
                record.groupIdsRaw = encodedGroupIDs([groupID])
            case 2:
                record.isPinned = true
            default:
                break
            }
            context.insert(record)
        }
        try context.save()
    }
}
