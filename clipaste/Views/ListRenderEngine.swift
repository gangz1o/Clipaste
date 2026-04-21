import SwiftUI
import AppKit

/// UI 层专属异步渲染缓存引擎。
/// ⚠️ 架构红线：这是整个项目中**唯一**允许持有 `AttributedString` 的位置。
/// ViewModel 和 Snapshot 绝不允许包含任何与 UI 排版相关的对象。
@MainActor
final class ListRenderEngine {

    static let shared = ListRenderEngine()

    // MARK: - 缓存

    /// 内存缓存：卡片 ID → 已排版的 AttributedString
    private var cache: [UUID: AttributedString] = [:]

    /// 正在后台排版中的任务集合，防止同一个 item 被重复解析。
    private var inflight: [UUID: Task<AttributedString?, Never>] = [:]

    // MARK: - 公开接口

    /// O(1) 缓存查询。缓存命中则 0 延迟渲染高亮文本。
    func cachedText(for id: UUID) -> AttributedString? {
        cache[id]
    }

    /// 触发后台排版（幂等）并返回当前 item 的已排版文本。
    /// - 从数据库按需加载 rtfData → 后台解析 → 回主线程写入缓存
    func prepareText(for item: ClipboardItem) async -> AttributedString? {
        let id = item.id
        if let cached = cache[id] {
            return cached
        }

        // 无 RTF 数据 → 无需排版
        guard item.hasRTF else { return nil }

        if let existingTask = inflight[id] {
            return await existingTask.value
        }

        let itemId = item.id

        let task: Task<AttributedString?, Never> = Task.detached(priority: .userInitiated) {
            guard let pasteRecord = await StorageManager.shared.loadPasteRecord(id: itemId) else {
                return nil
            }

            if let archive = ClipboardRichTextArchive.decode(from: pasteRecord.richTextArchiveData),
               archive.hasComplexPreviewRepresentations {
                return nil
            }

            guard Task.isCancelled == false, let data = pasteRecord.rtfData else {
                return nil
            }

            return Self.renderPreviewText(from: data)
        }

        inflight[id] = task
        let result = await task.value
        inflight[id] = nil

        if let result {
            cache[id] = result
        }

        return result
    }

    /// 清除指定卡片的缓存（编辑保存后调用）
    func invalidate(id: UUID) {
        cache.removeValue(forKey: id)
        inflight[id]?.cancel()
        inflight.removeValue(forKey: id)
    }

    /// 清除全部缓存（数据刷新后调用）
    func invalidateAll() {
        cache.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
    }
}

private extension ListRenderEngine {
    nonisolated static func renderPreviewText(from data: Data) -> AttributedString? {
        guard let nsAttrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return nil
        }

        let safeLength = min(300, nsAttrString.length)
        let truncated = nsAttrString.attributedSubstring(
            from: NSRange(location: 0, length: safeLength)
        )

        guard var swiftUIAttr = try? AttributedString(truncated, including: \.appKit) else {
            return nil
        }

        // 强制约束字号，防止编辑器里的巨大字号破坏列表 UI
        swiftUIAttr.font = .system(size: 13)
        return swiftUIAttr
    }
}
