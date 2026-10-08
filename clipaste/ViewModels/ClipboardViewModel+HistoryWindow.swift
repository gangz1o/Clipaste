import Foundation

/// 「全部」视图只展示连续载入的历史前缀。
///
/// 搜索 / 范围补齐会把窗口外的旧记录合并进 items，这些记录与已载入前缀之间
/// 隔着一段尚未载入的历史。如果在无筛选视图里直接展示，列表尾部会出现时间
/// 断层，继续滚动加载时中间的记录又会插进来。这里用前缀里排序最靠后的一条
/// 作为边界，边界之后的记录只在命中筛选 / 搜索时出现。
extension ClipboardViewModel {
    /// 记录是否落在连续载入的历史前缀内（含边界本身）。
    /// 新复制或被置顶的记录排序前移，会自然回到窗口内。
    func isWithinLoadedHistoryWindow(_ item: ClipboardItem) -> Bool {
        guard let historyWindowBoundary else { return true }
        return ClipboardItem.precedesInHistory(historyWindowBoundary, item) == false
    }

    /// 载入一页连续历史后更新边界。
    /// - Parameters:
    ///   - pageItems: 本页记录（顺序不限）。
    ///   - isComplete: 历史是否已全部载入；全部载入后不再需要边界。
    ///   - extendsCurrentWindow: 本页是否与现有前缀相连（继续加载 / 首屏合并），
    ///     相连时边界取两者中更靠后的一条。须在本页合并进 items 之前调用：
    ///     items 的 didSet 会立即按新边界重新过滤。
    func updateHistoryWindowBoundary(
        loadedPage pageItems: [ClipboardItem],
        isComplete: Bool,
        extendsCurrentWindow: Bool
    ) {
        guard isComplete == false,
              let pageBoundary = pageItems.max(by: ClipboardItem.precedesInHistory) else {
            historyWindowBoundary = nil
            return
        }

        // 没有边界说明现有 items 本身就是完整历史，整段都算在窗口内。
        let currentBoundary = extendsCurrentWindow
            ? (historyWindowBoundary ?? items.max(by: ClipboardItem.precedesInHistory))
            : nil
        guard let currentBoundary else {
            historyWindowBoundary = pageBoundary
            return
        }

        historyWindowBoundary = ClipboardItem.precedesInHistory(currentBoundary, pageBoundary)
            ? pageBoundary
            : currentBoundary
    }
}
