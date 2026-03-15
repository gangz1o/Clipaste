import SwiftUI
import AppKit
import Combine

/// UI 层专属异步渲染缓存引擎。
/// ⚠️ 架构红线：这是整个项目中**唯一**允许持有 `AttributedString` 的位置。
/// ViewModel 和 Snapshot 绝不允许包含任何与 UI 排版相关的对象。
@MainActor
final class ListRenderEngine: ObservableObject {

    static let shared = ListRenderEngine()

    // MARK: - 缓存

    /// 内存缓存：卡片 ID → 已排版的 AttributedString
    private var cache: [UUID: AttributedString] = [:]

    /// 正在后台排版中的任务集合，防止重复触发
    private var inflight: Set<UUID> = []

    // MARK: - 公开接口

    /// O(1) 缓存查询。缓存命中则 0 延迟渲染高亮文本。
    func cachedText(for id: UUID) -> AttributedString? {
        cache[id]
    }

    /// 触发后台排版（幂等）。缓存未命中时由 `.onAppear` 调用。
    /// - 从数据库按需加载 rtfData → 后台解析 → 回主线程写入缓存
    func prepareIfNeeded(for item: ClipboardItem) {
        let id = item.id
        // 缓存命中或已在排版中 → 短路返回
        guard cache[id] == nil, !inflight.contains(id) else { return }
        // 无 RTF 数据 → 无需排版
        guard item.hasRTF else { return }

        inflight.insert(id)

        let itemId = item.id

        _ = Task.detached(priority: .userInitiated) {
            // 1. 从数据库按需读取 RTF 二进制（绝不从 DTO 层获取）
            let rtfData: Data? = await MainActor.run {
                StorageManager.shared.fetchRecord(id: itemId)?.rtfData
            }

            guard let data = rtfData else {
                _ = await MainActor.run { [weak self = ListRenderEngine.shared] in
                    self?.inflight.remove(itemId)
                }
                return
            }

            // 2. 后台线程：RTF 词法解析 + 物理截断 + 排版组装
            let result: AttributedString? = {
                guard let nsAttrString = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ) else { return nil }

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
            }()

            // 3. 回主线程写入缓存
            await MainActor.run { [weak self = ListRenderEngine.shared] in
                guard let self else { return }
                self.inflight.remove(itemId)
                if let result {
                    self.cache[itemId] = result
                    self.objectWillChange.send()
                }
            }
        }
    }

    /// 清除指定卡片的缓存（编辑保存后调用）
    func invalidate(id: UUID) {
        cache.removeValue(forKey: id)
        inflight.remove(id)
        objectWillChange.send()
    }

    /// 清除全部缓存（数据刷新后调用）
    func invalidateAll() {
        cache.removeAll()
        inflight.removeAll()
        objectWillChange.send()
    }
}
