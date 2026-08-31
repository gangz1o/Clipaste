import Foundation

struct ClipboardFilterSnapshot: Sendable {
    let id: UUID
    let contentTypeRawValue: String
    let groupIDs: [String]
    let isPinned: Bool
    let searchableText: String
    let appName: String
}

enum ClipboardFilterResult: Sendable, Equatable {
    case completed([UUID])
    case cancelled
}

enum ClipboardFilterEngine {
    nonisolated static func filteredIDs(
        snapshots: [ClipboardFilterSnapshot],
        query: String,
        groupID: String?,
        typeFilterRawValue: String?,
        favoritesOnly: Bool
    ) async -> ClipboardFilterResult {
        var result: [UUID] = []
        result.reserveCapacity(snapshots.count)

        for (index, snapshot) in snapshots.enumerated() {
            if index.isMultiple(of: 32), Task.isCancelled {
                return .cancelled
            }
            if let typeFilterRawValue,
               snapshot.contentTypeRawValue != typeFilterRawValue {
                continue
            }
            if let groupID, snapshot.groupIDs.contains(groupID) == false { continue }
            if favoritesOnly, snapshot.isPinned == false { continue }

            if query.isEmpty == false {
                guard snapshot.searchableText.localizedStandardContains(query)
                        || snapshot.appName.localizedStandardContains(query) else {
                    continue
                }
            }

            result.append(snapshot.id)
        }

        return Task.isCancelled ? .cancelled : .completed(result)
    }
}
