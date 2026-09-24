import Foundation
import SwiftData

@main
enum ClipboardGroupRepairTests {
    static func main() async throws {
        let container = try ModelContainer(
            for: ClipboardGroupModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let actor = ClipboardStoreActor(modelContainer: container)
        try await actor.seed()

        let repairedCount = await actor.repairDuplicateGroups()
        precondition(repairedCount == 2, "Only duplicate tombstone rows should be removed")

        let rows = try await actor.rows()
        let rowCounts = Dictionary(grouping: rows, by: \.id).mapValues(\.count)
        precondition(rowCounts == ["live": 1, "live-dup": 2, "tombstone-dup": 1, "mixed": 1, "tombstone": 1],
                     "Live duplicates must be kept; tombstone duplicates collapse to one row")

        let tombstone = rows.first { $0.id == "tombstone-dup" }
        precondition(tombstone?.deletedAt == Date(timeIntervalSince1970: 2_000) && tombstone?.deletedByDevice == "B",
                     "The latest deletion wins")
        precondition(rows.first { $0.id == "mixed" }?.deletedAt != nil, "Deletion must spread to live copies")

        let activeIDs = try await actor.activeItems().map(\.id)
        precondition(activeIDs.sorted() == ["live", "live-dup"], "Duplicate live rows must be shown once")

        let secondPass = await actor.repairDuplicateGroups()
        precondition(secondPass == 0, "Repair must be idempotent")
        print("ClipboardGroupRepairTests passed")
    }
}
