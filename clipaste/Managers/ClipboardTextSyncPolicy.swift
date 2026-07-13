import Foundation

/// 文本入库策略:CloudKit 对 CKRecord 的内联字段有 1MB 硬上限,超限记录会让
/// NSPersistentCloudKitContainer 的导出队列永久卡死(partialFailure 无限重试,
/// 后续所有变更都无法上传)。因此超过 `inlineLimitBytes` 的文本拆成两份存储:
/// - `plainText` 只保留截断后的前缀(内联,供搜索/列表预览/谓词使用)
/// - `fullTextData` 保存完整 UTF-8 数据(`.externalStorage`,同步时走 CKAsset,无 1MB 限制)
enum ClipboardTextSyncPolicy {
    /// 内联 plainText 的最大 UTF-8 字节数。须与记录中其他内联字段合计后
    /// 仍留有充足余量,远低于 CloudKit 1MB 上限。
    nonisolated static let inlineLimitBytes = 200_000

    struct StoredText {
        let inlineText: String?
        let fullTextData: Data?
        let isTruncated: Bool
    }

    /// 按当前策略拆分待入库文本。`limitBytes` 为用户设置的同步大小上限
    /// (nil = 无限制);超过上限的文本不保留全文,只存截断前缀并打标记。
    nonisolated static func storedText(for text: String?, limitBytes: Int?) -> StoredText {
        guard let text else {
            return StoredText(inlineText: nil, fullTextData: nil, isTruncated: false)
        }

        let byteCount = text.utf8.count
        guard byteCount > inlineLimitBytes else {
            return StoredText(inlineText: text, fullTextData: nil, isTruncated: false)
        }

        let inlineText = utf8Prefix(text, maxBytes: inlineLimitBytes)

        if let limitBytes, byteCount > limitBytes {
            return StoredText(inlineText: inlineText, fullTextData: nil, isTruncated: true)
        }

        return StoredText(inlineText: inlineText, fullTextData: Data(text.utf8), isTruncated: false)
    }

    /// 读取当前用户偏好并拆分文本。iCloud 同步关闭时不施加大小上限
    /// (本地 SQLite 没有 1MB 内联限制,但依旧拆分,保证之后切换到云路由
    /// 时记录已经是合规形态)。
    nonisolated static func storedTextUsingPreferences(
        for text: String?,
        defaults: UserDefaults = .standard
    ) -> StoredText {
        storedText(for: text, limitBytes: preferredLimitBytes(defaults: defaults))
    }

    nonisolated static func preferredLimitBytes(defaults: UserDefaults = .standard) -> Int? {
        guard defaults.bool(forKey: "enable_icloud_sync") else { return nil }

        let rawValue = defaults.string(forKey: TextSyncSizeLimit.defaultsKey)
            ?? TextSyncSizeLimit.unlimited.rawValue
        return (TextSyncSizeLimit(rawValue: rawValue) ?? .unlimited).limitBytes
    }

    /// 在 UTF-8 字节边界上安全截断,绝不切碎多字节字符。
    nonisolated static func utf8Prefix(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes, maxBytes > 0 else { return text }

        var data = Data(text.utf8.prefix(maxBytes))
        // UTF-8 单字符最长 4 字节,最多回退 3 次即可落在字符边界上。
        while data.isEmpty == false, String(data: data, encoding: .utf8) == nil {
            data.removeLast()
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}
