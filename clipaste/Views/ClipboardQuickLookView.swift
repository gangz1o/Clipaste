import SwiftUI

struct ClipboardQuickLookView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.contentType == .image,
               let url = item.originalImageURL ?? item.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let img = NSImage(data: data) {
                // 图片预览：优先读取 Originals/ 下的全尺寸高清原图
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 600)
                    .padding(16)

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
                // 文本预览：使用原生 NSTextView 引擎，支持百万字级懒加载渲染
                // 设定 20 万字节的绝对物理上限，防止内存炸裂
                let fullText = item.rawText ?? item.textPreview
                let safeText: String = {
                    if fullText.utf8.count > 200_000 {
                        return String(fullText.prefix(100_000)) + "\n\n... (文本过于巨大，为保护内存已折叠预览，粘贴时不受影响)"
                    }
                    return fullText
                }()

                NativeTextView(text: safeText)
                    .frame(minWidth: 400, idealWidth: 500, maxWidth: 700, minHeight: 300, idealHeight: 400, maxHeight: 600)
                    .padding(16)
            }
        }
        // Popover 原生自带材质背景，无需额外设置
    }
}
