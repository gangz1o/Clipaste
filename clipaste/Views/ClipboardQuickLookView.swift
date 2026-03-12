import SwiftUI

struct ClipboardQuickLookView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.contentType == .image, let url = item.thumbnailURL,
               let img = NSImage(contentsOf: url) {
                // 图片预览：限制最大宽高，保持精美比例
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 600)
                    .padding(16)

            } else if let parsedColor = ColorParser.extractColor(from: item.rawText ?? item.textPreview) {
                // 颜色预览：大色块 + 对比色等宽文字
                ZStack {
                    parsedColor
                    Text(item.rawText ?? item.textPreview)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(parsedColor.isDark ? .white : .black)
                }
                .frame(width: 280, height: 120)

            } else {
                // 文本预览：开启原生鼠标拖拽选中 + Cmd+C 复制
                ScrollView {
                    Text(item.rawText ?? item.textPreview)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                }
                .frame(width: 400)
                .frame(minHeight: 100, maxHeight: 500)
            }
        }
        // Popover 原生自带材质背景，无需额外设置
    }
}
