import Foundation

@main
enum ClipboardSearchSupplementPolicyTests {
    static func main() {
        let existingID = UUID()
        let existing = [
            ClipboardItemDeduplicationKey(id: existingID, contentHash: "existing-hash")
        ]
        let uniqueID = UUID()
        let candidates = [
            ClipboardItemDeduplicationKey(id: UUID(), contentHash: "existing-hash"),
            ClipboardItemDeduplicationKey(id: existingID, contentHash: "changed-hash"),
            ClipboardItemDeduplicationKey(id: uniqueID, contentHash: "unique-hash"),
            ClipboardItemDeduplicationKey(id: UUID(), contentHash: "unique-hash")
        ]

        let acceptedIndexes = ClipboardItemDeduplicationPolicy.uniqueAppendIndexes(
            existing: existing,
            incoming: candidates
        )

        precondition(
            acceptedIndexes == [2],
            "supplemental search must append only candidates with a new ID and content hash"
        )

        print("ClipboardSearchSupplementPolicyTests passed")
    }
}
