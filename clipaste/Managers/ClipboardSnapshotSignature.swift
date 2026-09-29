import Foundation

/// 首屏快照签名：判断持久化存储的 RemoteChange 是否带来了界面尚未知晓的变化。
///
/// NSPersistentStoreRemoteChange 对本进程自己的每次保存也会发出。记录写入已经通过
/// `clipboardRecordDidChange` 增量送达界面，这类回声不应再触发整页刷新。
nonisolated struct ClipboardSnapshotSignature: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let contentHash: String
        let timestamp: TimeInterval
        let fingerprint: String
    }

    let groupSignature: String
    /// 按时间倒序的首屏条目。
    let entries: [Entry]
    let windowLimit: Int

    /// 新旧签名的差异能否全部由本进程已增量广播过的记录变更（`localHashes`）解释。
    /// 只允许误判为"有外部变化"（多一次整页刷新，无害），不允许漏判。
    func differsOnlyByLocalChanges(
        from previous: ClipboardSnapshotSignature,
        localHashes: Set<String>
    ) -> Bool {
        // 分组变更不走记录通知，一律按外部变化处理。
        guard groupSignature == previous.groupSignature, windowLimit == previous.windowLimit else {
            return false
        }

        let previousByHash = Dictionary(
            previous.entries.map { ($0.contentHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentHashes = Set(entries.map(\.contentHash))

        for entry in entries where localHashes.contains(entry.contentHash) == false {
            guard previousByHash[entry.contentHash] == entry else { return false }
        }

        // 被本地新记录挤出首屏窗口的旧条目不算外部变化；其余消失的条目按外部删除处理。
        let windowFloor = entries.count >= windowLimit ? entries.last?.timestamp : nil
        for entry in previous.entries
        where localHashes.contains(entry.contentHash) == false && currentHashes.contains(entry.contentHash) == false {
            guard let windowFloor, entry.timestamp <= windowFloor else { return false }
        }

        return true
    }
}
