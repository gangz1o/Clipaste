import Foundation
import SwiftData

extension ClipboardStoreActor {
    func cleanUpExpiredRecords(before expirationDate: Date) {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.timestamp < expirationDate && $0.isPinned == false && $0.topPinOrder == 0 }
        )

        do {
            let expiredRecords = try modelContext.fetch(descriptor).filter { record in
                // Both legacy and multi-group memberships represent user-kept content.
                // Don't require the group definition: CloudKit may deliver it later.
                normalizedGroupIDs(
                    primaryGroupID: record.groupId,
                    groupIdsRaw: record.groupIdsRaw
                ).isEmpty
            }
            guard !expiredRecords.isEmpty else { return }

            for record in expiredRecords {
                modelContext.delete(record)
            }

            try markSyncAnchorUpdated()
            try modelContext.save()
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        } catch {
            print("❌ [清理任务] 清理过期记录失败: \(error)")
        }
    }
}
