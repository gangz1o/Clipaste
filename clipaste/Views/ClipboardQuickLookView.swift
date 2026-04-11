import SwiftUI

struct ClipboardQuickLookView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.contentType == .image {
                ClipboardQuickLookImageView(viewModel: viewModel)
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
                ClipboardQuickLookTextContent(item: item)
            }
        }
        // Popover 原生自带材质背景，无需额外设置
    }
}

private struct ClipboardQuickLookTextContent: View {
    let item: ClipboardItem

    @State private var highlightedAttr: NSAttributedString?

    private var safeText: String {
        let fullText = item.rawText ?? item.textPreview
        if fullText.utf8.count > 200_000 {
            return String(fullText.prefix(100_000))
                + "\n\n"
                + String(localized: "Preview truncated to protect memory. Pasting is not affected.")
        }
        return fullText
    }

    var body: some View {
        NativeTextView(text: safeText, attributedText: highlightedAttr)
            .frame(
                minWidth: 400,
                idealWidth: 500,
                maxWidth: 700,
                minHeight: 300,
                idealHeight: 400,
                maxHeight: 600
            )
            .padding(16)
            .task(id: item.contentHash) { @MainActor in
                highlightedAttr = ClipboardQuickLookTextLoader.loadHighlightedText(for: item)
            }
    }
}

private enum ClipboardQuickLookTextLoader {
    @MainActor
    static func loadHighlightedText(for item: ClipboardItem) -> NSAttributedString? {
        guard item.hasRTF else {
            return nil
        }

        let rtfData = StorageManager.shared.fetchRecord(id: item.id)?.rtfData

        guard let rtfData else {
            return nil
        }

        return try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}
