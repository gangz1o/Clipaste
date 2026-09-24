import Foundation
import SwiftData

extension ClipboardStoreActor {
    /// 跨路由合并时云端副本还没下载,同一分组 ID 会先被再建一行,随后 CloudKit 送达原行。
    /// 两行字段相同、底层 CloudKit 记录名不可见,各设备无法就保留哪一行达成一致,
    /// 并发删除可能让仍在使用的分组定义彻底消失。因此只收拢墓碑:删除标记单向扩散到
    /// 同 ID 的所有行,之后仅保留一行;仍在使用的重复行由读取路径按 ID 去重。
    func repairDuplicateGroups() -> Int {
        do {
            let groups = try modelContext.fetch(FetchDescriptor<ClipboardGroupModel>())
            var repairedCount = 0

            for duplicates in Dictionary(grouping: groups, by: \.id).values where duplicates.count > 1 {
                guard let latestDeletedAt = duplicates.compactMap(\.deletedAt).max() else { continue }
                let deletedByDevice = duplicates.first { $0.deletedAt == latestDeletedAt }?.deletedByDevice ?? ""

                for (index, group) in duplicates.enumerated() {
                    if index == 0 {
                        group.deletedAt = latestDeletedAt
                        group.deletedByDevice = deletedByDevice
                    } else {
                        modelContext.delete(group)
                        repairedCount += 1
                    }
                }
            }

            if repairedCount > 0 {
                try markSyncAnchorUpdated()
                try modelContext.save()
            }

            return repairedCount
        } catch {
            print("❌ [ClipboardStoreActor] 修复重复分组失败: \(error)")
            return 0
        }
    }
}
