import Foundation

@main
enum ClipboardSnapshotSignatureTests {
    static func main() {
        let limit = 4
        let base = signature([("d", 4), ("c", 3), ("b", 2), ("a", 1)], limit: limit)

        // 本地新增一条，最旧的一条被挤出首屏窗口：回声。
        let localInsert = signature([("e", 5), ("d", 4), ("c", 3), ("b", 2)], limit: limit)
        precondition(localInsert.differsOnlyByLocalChanges(from: base, localHashes: ["e"]))

        // 同样的变化但本地没有广播过 e：外部变化。
        precondition(localInsert.differsOnlyByLocalChanges(from: base, localHashes: []) == false)

        // 本地复制已有内容（置顶到最前，时间戳变化）：回声。
        let localBump = signature([("b", 5), ("d", 4), ("c", 3), ("a", 1)], limit: limit)
        precondition(localBump.differsOnlyByLocalChanges(from: base, localHashes: ["b"]))

        // 本地新增的同时有一条非本地记录的指纹变化（例如置顶状态）：外部变化。
        let mixed = signature([("e", 5, ""), ("d", 4, ""), ("c", 3, "pinned"), ("b", 2, "")], limit: limit)
        precondition(mixed.differsOnlyByLocalChanges(from: base, localHashes: ["e"]) == false)

        // 窗口未满时有非本地记录消失：外部删除。
        let small = signature([("c", 3), ("b", 2), ("a", 1)], limit: limit)
        let remoteDelete = signature([("c", 3), ("a", 1)], limit: limit)
        precondition(remoteDelete.differsOnlyByLocalChanges(from: small, localHashes: []) == false)

        // 本地删除：回声。
        precondition(remoteDelete.differsOnlyByLocalChanges(from: small, localHashes: ["b"]))

        // 窗口已满时中间的非本地记录消失（不是被挤出底部）：外部删除。
        let middleGone = signature([("e", 5), ("d", 4), ("b", 2), ("a", 1)], limit: limit)
        precondition(middleGone.differsOnlyByLocalChanges(from: base, localHashes: ["e"]) == false)

        // 外部新增一条（本地另有变更）：外部变化。
        let remoteInsert = signature([("f", 6), ("e", 5), ("d", 4), ("c", 3)], limit: limit)
        precondition(remoteInsert.differsOnlyByLocalChanges(from: base, localHashes: ["e"]) == false)

        // 分组变化一律按外部变化处理。
        let groupChanged = signature([("e", 5), ("d", 4), ("c", 3), ("b", 2)], limit: limit, groups: "g2")
        precondition(groupChanged.differsOnlyByLocalChanges(from: base, localHashes: ["e"]) == false)

        print("ClipboardSnapshotSignatureTests passed")
    }

    private static func signature(
        _ rows: [(String, TimeInterval, String)],
        limit: Int,
        groups: String = "g1"
    ) -> ClipboardSnapshotSignature {
        ClipboardSnapshotSignature(
            groupSignature: groups,
            entries: rows.map { .init(contentHash: $0.0, timestamp: $0.1, fingerprint: "\($0.0)|\($0.2)") },
            windowLimit: limit
        )
    }

    private static func signature(
        _ rows: [(String, TimeInterval)],
        limit: Int,
        groups: String = "g1"
    ) -> ClipboardSnapshotSignature {
        signature(rows.map { ($0.0, $0.1, "") }, limit: limit, groups: groups)
    }
}
