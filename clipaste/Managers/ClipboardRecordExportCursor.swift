import Foundation
import SwiftData

/// 切换存储路由(本地 ↔ iCloud)、收藏恢复时按"最新优先"分批导出记录。
///
/// 旧做法是每批"排序 + OFFSET",每批都要把整表(含内联大字段)重新排序,
/// 几百 MB 的库切换同步要卡很久。macOS 15+ 首批时只排序一次、只读主键做快照,
/// 之后每批按主键取行,位置由游标自己记录。macOS 14 没有 `fetchIdentifiers`,回退到 OFFSET 分页。
///
/// 只能被一个调用方顺序使用;返回空批表示导出完毕。
actor ClipboardRecordExportCursor {
    private let container: ModelContainer
    private let pinnedOnly: Bool
    private var identifiers: [PersistentIdentifier]?
    private var position = 0

    init(container: ModelContainer, pinnedOnly: Bool) {
        self.container = container
        self.pinnedOnly = pinnedOnly
    }

    /// 每批用新的读 actor:同一个 ModelContext 会一直持有读过的记录,整表导出时内存随表增长。
    /// 读 actor 在调用方线程上执行;游标自身不在 MainActor,所以导出不会占用主线程。
    private func makeReadActor() -> ClipboardStoreActor {
        ClipboardStoreActor(modelContainer: container)
    }

    func nextBatch(limit: Int) async throws -> ClipboardStoreExport {
        guard limit > 0 else { return ClipboardStoreExport(records: [], groups: []) }

        guard #available(macOS 15, *) else {
            let batch = pinnedOnly
                ? try await makeReadActor().exportPinnedRecordBatch(offset: position, limit: limit)
                : ClipboardStoreExport(
                    records: try await makeReadActor().exportRecordBatch(offset: position, limit: limit),
                    groups: []
                )
            position += batch.records.count
            return batch
        }

        let snapshot: [PersistentIdentifier]
        if let identifiers {
            snapshot = identifiers
        } else {
            snapshot = try await makeReadActor().exportRecordIdentifiers(pinnedOnly: pinnedOnly)
            identifiers = snapshot
        }

        // 某批主键可能全部在快照之后被删除,继续往后取,不能用空批提前结束导出。
        while position < snapshot.count {
            let slice = Array(snapshot[position..<min(position + limit, snapshot.count)])
            let batch = try await makeReadActor().exportRecordBatch(identifiers: slice, includingGroups: pinnedOnly)
            position += batch.consumedCount
            if batch.export.records.isEmpty == false {
                return batch.export
            }
        }

        return ClipboardStoreExport(records: [], groups: [])
    }
}
