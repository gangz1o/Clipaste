import Foundation
import SwiftData

@main
enum ClipboardRetentionTests {
    static func main() async throws {
        let container = try ModelContainer(
            for: ClipboardRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let actor = ClipboardStoreActor(modelContainer: container)
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        try await actor.seed(cutoff: cutoff)
        await actor.cleanUpExpiredRecords(before: cutoff)
        let expected: Set<String> = [
            "boundary", "recent", "favorite", "legacy-group", "multi-group", "imported", "legacy-invalid-json"
        ]
        let firstPass = try await actor.hashes()
        precondition(firstPass == expected, "Cleanup must retain favorites and all group representations")
        await actor.cleanUpExpiredRecords(before: cutoff)
        let secondPass = try await actor.hashes()
        precondition(secondPass == expected, "Repeated cleanup must preserve protected records")

        try await actor.removeGroupMemberships(hash: "multi-group")
        await actor.cleanUpExpiredRecords(before: cutoff)
        let afterRemoval = try await actor.hashes()
        precondition(afterRemoval == expected.subtracting(["multi-group"]))
        print("ClipboardRetentionTests passed")
    }
}
