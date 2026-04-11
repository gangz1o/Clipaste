import AppKit
import Foundation
import Highlightr

// ⚠️ AI DEV WARNING: PERFORMANCE GUARD - DO NOT REMOVE
// 独立的语法高亮服务（物理隔离层）。
// 管理 Highlightr 引擎的核心实例和主题配置，所有高亮运算均在后台线程执行。
// 主题根据系统 Light/Dark Mode 动态切换：浅色用 "xcode"，深色用 "atom-one-dark"。
// ⚠️ 内存暴涨防御：严禁将超大纯文本全量转换为 RTF（体积膨胀 20 倍）！
//    RTF 渲染用数据严格物理截断到 5000 字以内，用户完整文本保存在 plainText 字段中不受影响。
final class SyntaxHighlightService: @unchecked Sendable {
    static let shared = SyntaxHighlightService()

    /// ⚠️ Smart Sniffer 专用：同步判断文本是否具有代码特征。
    /// 录入时由 ClipboardMonitor 调用，决定 typeRawValue 的打标。
    static func looksLikeCode(_ text: String) -> Bool {
        ClipboardContentClassifier.isLikelyCode(text)
    }

    // 注意：Highlightr 实例的创建开销较大，保持为单例复用
    nonisolated(unsafe) private let highlightr: Highlightr?

    /// UserDefaults 中的高亮主题键名（暂保留，未来可在设置中覆盖自动检测）
    static let themeKey = "codeHighlightTheme"

    // ⚠️ AI DEV WARNING: PERFORMANCE GUARD - DO NOT REMOVE
    // 送入 Highlightr 引擎的文本绝对物理上限。超过此长度的部分直接截断，
    // 只用于 UI 预览渲染，用户粘贴时始终使用 plainText 完整原文。
    private static let maxHighlightLength = 5000

    private init() {
        highlightr = Highlightr()
        // 不在 init 中写死主题，将其移交到动态处理管线中
    }

    /// 刷新主题（当用户在设置中切换时调用）
    func reloadTheme() {
        // 空实现：主题现在每次高亮时动态决定，无需全局刷新
    }

    /// 异步处理纯文本：返回高亮后的 RTF Data（代码）或基础格式 RTF（普通文本）。
    /// 所有高强度正则匹配运算均在后台线程执行，绝不阻塞主线程。
    /// 用户完整原文始终保存在 plainText 字段中，此处 RTF 仅用于 UI 预览渲染。
    func processAndHighlight(text: String) async -> Data? {
        // 简单的试探：如果文本太短，直接跳过，节省性能
        if text.count < 10 {
            return nil
        }

        // 1. ⚠️ 极其核心：必须在主线程安全读取 macOS 当前的深浅外观模式
        let isDarkMode = await MainActor.run {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        // 浅色模式用苹果原生的 xcode 主题(字是黑的)，深色用 atom-one-dark(字是白的)
        let themeName = isDarkMode ? "atom-one-dark" : "xcode"

        let looksLikeCode = ClipboardContentClassifier.shouldHighlightAsCode(text)

        // ⚠️ AI DEV WARNING: PERFORMANCE GUARD - DO NOT REMOVE
        // 内存泄压阀：无论是代码还是普通文本，送入 RTF 转换管线的数据严格截断到 maxHighlightLength。
        // 用户的完整文本始终安全保存在 plainText 字段中，粘贴时不受任何影响。
        let safeText = text.count > Self.maxHighlightLength
            ? String(text.prefix(Self.maxHighlightLength))
            : text

        // 2. 将高强度的正则匹配与渲染放入后台线程
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                if looksLikeCode, let highlightr = self.highlightr {
                    // ── 代码路径：通过 Highlightr 引擎高亮 ──────────────────────
                    highlightr.setTheme(to: themeName)
                    highlightr.theme.codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

                    if let attributedString = highlightr.highlight(safeText, as: nil, fastRender: true) {
                        let range = NSRange(location: 0, length: attributedString.length)
                        let rtfData = try? attributedString.data(
                            from: range,
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                        )
                        continuation.resume(returning: rtfData)
                        return
                    }
                }

                // ── 兜底路径：非代码文本或 Highlightr 失败 ──────────────────────
                // ⚠️ AI DEV WARNING: PERFORMANCE GUARD - DO NOT REMOVE
                // 内存暴涨防御：严禁将超大纯文本全量转换为 RTF (体积会膨胀 20 倍)！
                // UI 预览最多只展示 2000 字，此处将 RTF 渲染用的数据严格物理截断到 5000 字以内。
                // 注意：用户真实的完整文本依然安全地保存在 plainText 字段中，不影响后续的完整粘贴。
                let attrString = NSAttributedString(string: safeText, attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.textColor
                ])

                let range = NSRange(location: 0, length: attrString.length)
                let rtfData = try? attrString.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                continuation.resume(returning: rtfData)
            }
        }
    }
}
