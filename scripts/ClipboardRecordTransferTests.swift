import Foundation
import SwiftData

@main
enum ClipboardRecordTransferTests {
    static func main() async throws {
        try await testExportOrderMatchesSortedPaging()
        try await testTopPinSurvivesStoreTransfer()
        try await testPinnedExportCarriesReferencedGroups()
        try await testByteBudgetTruncationKeepsEveryRecord()
        try await testRecordsDeletedAfterSnapshotDoNotEndExport()
        try await testDuplicateRepairMergesAcrossBatches()
        print("ClipboardRecordTransferTests passed")
    }

    private static func testExportOrderMatchesSortedPaging() async throws {
        let container = try makeTemporaryContainer()
        let actor = ClipboardStoreActor(modelContainer: container)
        try await actor.seed(count: 300)

        let batches = try await drain(ClipboardRecordExportCursor(container: container, pinnedOnly: false), limit: 128)
        let exported = batches.flatMap(\.records).map(\.contentHash)
        let expected = try await actor.expectedHashes(pinnedOnly: false)
        precondition(exported == expected, "Export must keep newest-first order without gaps or repeats")
        precondition(batches.map(\.records.count) == [128, 128, 44])
        precondition(batches.allSatisfy { $0.groups.isEmpty }, "Full export carries groups separately")
    }

    private static func testTopPinSurvivesStoreTransfer() async throws {
        let source = try makeTemporaryContainer()
        let sourceActor = ClipboardStoreActor(modelContainer: source)
        try await sourceActor.seed(count: 3)
        let batches = try await drain(ClipboardRecordExportCursor(container: source, pinnedOnly: false), limit: 128)
        let target = try makeTemporaryContainer()
        let targetActor = ClipboardStoreActor(modelContainer: target)
        for batch in batches { try await targetActor.importStoreExport(batch) }
        let restored = try await drain(ClipboardRecordExportCursor(container: target, pinnedOnly: false), limit: 128)
        let pinned = restored.flatMap(\.records).first { $0.contentHash == "r0" }
        precondition(pinned?.topPinOrder == 1234, "Store transfers must preserve top pin order")
    }

    private static func testPinnedExportCarriesReferencedGroups() async throws {
        let container = try makeTemporaryContainer()
        let actor = ClipboardStoreActor(modelContainer: container)
        try await actor.seed(count: 300)

        let batches = try await drain(ClipboardRecordExportCursor(container: container, pinnedOnly: true), limit: 7)
        let exported = batches.flatMap(\.records).map(\.contentHash)
        let expected = try await actor.expectedHashes(pinnedOnly: true)
        precondition(exported == expected && exported.count == 30, "Pinned export must return only favorites")
        precondition(batches.allSatisfy { $0.groups.map(\.id) == ["pinned-group"] },
                     "Pinned batches must include only the groups they reference")
    }

    private static func testByteBudgetTruncationKeepsEveryRecord() async throws {
        let container = try makeTemporaryContainer()
        let actor = ClipboardStoreActor(modelContainer: container)
        // 2 MB per record: a 128-record slice exceeds the 96 MB batch budget.
        try await actor.seed(count: 70, imageBytes: 2 * 1_024 * 1_024)

        let batches = try await drain(ClipboardRecordExportCursor(container: container, pinnedOnly: false), limit: 128)
        let exported = batches.flatMap(\.records).map(\.contentHash)
        let expected = try await actor.expectedHashes(pinnedOnly: false)
        precondition(batches.count > 1, "Budget must split the slice into several batches")
        precondition(exported == expected, "Truncated batches must resume at the first unexported record")
    }

    private static func testRecordsDeletedAfterSnapshotDoNotEndExport() async throws {
        let container = try makeTemporaryContainer()
        let actor = ClipboardStoreActor(modelContainer: container)
        try await actor.seed(count: 300)
        let expected = try await actor.expectedHashes(pinnedOnly: false)

        let cursor = ClipboardRecordExportCursor(container: container, pinnedOnly: false)
        let first = try await cursor.nextBatch(limit: 100)
        try await actor.deleteRecords(hashes: Set(expected[100..<250]))
        let rest = try await drain(cursor, limit: 100)

        let exported = (first.records + rest.flatMap(\.records)).map(\.contentHash)
        precondition(exported == Array(expected[0..<100] + expected[250..<300]),
                     "A fully deleted slice must be skipped, not treated as the end of the export")
    }

    private static func testDuplicateRepairMergesAcrossBatches() async throws {
        let container = try makeTemporaryContainer()
        let actor = ClipboardStoreActor(modelContainer: container)
        // 600 rows over more than two 256-row scan batches, each hash stored 3 times.
        try await actor.seed(count: 600, hash: { "dup-\($0 % 200)" })

        let repaired = await actor.repairDuplicateRecords()
        let remaining = try await actor.storedHashes()
        precondition(repaired == 400, "Expected 400 merged duplicates, got \(repaired)")
        precondition(remaining.count == 200 && Set(remaining).count == 200)
        let repairedAgain = await actor.repairDuplicateRecords()
        precondition(repairedAgain == 0)
    }
}
