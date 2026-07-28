import Foundation

struct ClipboardItemDeduplicationKey: Hashable, Sendable {
    let id: UUID
    let contentHash: String
}

enum ClipboardItemDeduplicationPolicy {
    nonisolated static func uniqueAppendIndexes(
        existing: [ClipboardItemDeduplicationKey],
        incoming: [ClipboardItemDeduplicationKey]
    ) -> [Int] {
        var knownIDs = Set(existing.map(\.id))
        var knownHashes = Set(existing.map(\.contentHash))
        var acceptedIndexes: [Int] = []
        acceptedIndexes.reserveCapacity(incoming.count)

        for (index, candidate) in incoming.enumerated() {
            guard knownIDs.contains(candidate.id) == false,
                  knownHashes.contains(candidate.contentHash) == false else {
                continue
            }

            knownIDs.insert(candidate.id)
            knownHashes.insert(candidate.contentHash)
            acceptedIndexes.append(index)
        }

        return acceptedIndexes
    }
}
