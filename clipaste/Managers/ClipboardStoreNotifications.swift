import Foundation

enum ClipboardRecordChangeKind: String, Sendable {
    case upsert
    case enrichment
    case content
    case reorder
    case delete
}

struct ClipboardRecordChange: Sendable {
    let contentHash: String
    let kind: ClipboardRecordChangeKind
}

private enum ClipboardRecordChangeUserInfoKey {
    static let contentHash = "contentHash"
    static let kind = "kind"
}

extension Notification.Name {
    nonisolated static let clipboardRecordDidChange = Notification.Name("clipboardRecordDidChange")
}

extension Notification {
    var clipboardRecordChange: ClipboardRecordChange? {
        guard name == .clipboardRecordDidChange,
              let userInfo,
              let contentHash = userInfo[ClipboardRecordChangeUserInfoKey.contentHash] as? String,
              let rawKind = userInfo[ClipboardRecordChangeUserInfoKey.kind] as? String,
              let kind = ClipboardRecordChangeKind(rawValue: rawKind) else {
            return nil
        }

        return ClipboardRecordChange(contentHash: contentHash, kind: kind)
    }
}
