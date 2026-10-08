import Foundation
import SwiftData

extension ClipboardStoreActor {
    func setTopPin(hash: String, order: Double) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        do {
            let records = try modelContext.fetch(descriptor)
            guard !records.isEmpty else { return }
            for record in records {
                record.topPinOrder = order
            }
            try markSyncAnchorUpdated()
            try modelContext.save()
            NotificationCenter.default.post(
                name: .clipboardRecordDidChange,
                object: nil,
                userInfo: ["contentHash": hash, "kind": ClipboardRecordChangeKind.reorder.rawValue]
            )
        } catch {
            modelContext.rollback()
            print("❌ [ClipboardStoreActor] Pin to top failed: \(error)")
        }
    }
}
