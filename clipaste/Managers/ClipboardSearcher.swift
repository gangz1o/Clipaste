import Foundation
import SwiftData

@ModelActor
actor ClipboardSearcher {
    func searchAndMap(searchText: String, fetchLimit: Int? = nil, offset: Int = 0) async -> [ClipboardItem] {
        let query = searchText
        var descriptor: FetchDescriptor<ClipboardRecord>

        if query.isEmpty {
            descriptor = FetchDescriptor<ClipboardRecord>(
                sortBy: [
                    SortDescriptor(\.topPinOrder, order: .reverse),
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .forward)
                ]
            )
        } else {
            let predicate = #Predicate<ClipboardRecord> { record in
                (record.plainText?.localizedStandardContains(query) == true) ||
                (record.appLocalizedName?.localizedStandardContains(query) == true)
            }

            descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.topPinOrder, order: .reverse),
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .forward)
                ]
            )
        }

        if let fetchLimit, fetchLimit > 0 {
            descriptor.fetchLimit = fetchLimit
        }

        if offset > 0 {
            descriptor.fetchOffset = offset
        }

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = records.map { record in
            ClipboardRecordSnapshot.makeFromRecord(record)
        }

        return snapshots.map { StorageManager.makeClipboardItem(from: $0) }
    }
}
