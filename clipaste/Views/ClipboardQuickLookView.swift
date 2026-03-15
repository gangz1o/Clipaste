import SwiftUI

struct ClipboardQuickLookView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.contentType == .image {
                ClipboardQuickLookImageView(itemID: item.id)
            } else if let parsedColor = item.fastParsedColor {
                // 颜色预览：大色块 + 对比色等宽文字
                ZStack {
                    parsedColor
                    Text(item.rawText ?? item.textPreview)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(parsedColor.isDark ? .white : .black)
                }
                .frame(width: 280, height: 120)

            } else {
                // 文本预览：使用 NativeTextView 引擎（NSTextView 支持深色背景 + 语法高亮色彩完美搭配）
                let fullText = item.rawText ?? item.textPreview
                let safeText: String = {
                    if fullText.utf8.count > 200_000 {
                        return String(fullText.prefix(100_000)) + "\n\n... (文本过于巨大，为保护内存已折叠预览，粘贴时不受影响)"
                    }
                    return fullText
                }()

                // ⚠️ 架构升级：从数据库按需加载 RTF，不依赖 DTO 层
                let highlightedAttr: NSAttributedString? = {
                    guard let record = StorageManager.shared.fetchRecord(id: item.id),
                          let data = record.rtfData else { return nil }
                    return try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                }()

                NativeTextView(text: safeText, attributedText: highlightedAttr)
                    .frame(minWidth: 400, idealWidth: 500, maxWidth: 700, minHeight: 300, idealHeight: 400, maxHeight: 600)
                    .padding(16)
            }
        }
        // Popover 原生自带材质背景，无需额外设置
    }
}
