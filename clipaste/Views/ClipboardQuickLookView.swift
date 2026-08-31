import SwiftUI

struct ClipboardQuickLookView: View {
    let item: ClipboardItem
    var viewModel: ClipboardViewModel

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

    private var isCodeContent: Bool {
        item.contentType == .code
    }

    private var safeText: String {
        let fullText = item.rawText ?? item.textPreview
        if fullText.utf8.count > 200_000 {
            return String(fullText.prefix(100_000))
                + "\n\n"
                + String(localized: "Preview truncated to protect memory. Pasting is not affected.")
        }
        return fullText
    }

    private var previewLineCount: Int {
        max(safeText.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }

    private var previewMinWidth: CGFloat {
        isCodeContent ? 360 : 400
    }

    private var previewIdealWidth: CGFloat {
        isCodeContent ? 460 : 500
    }

    private var previewMaxWidth: CGFloat {
        700
    }

    private var previewMinHeight: CGFloat {
        isCodeContent ? 96 : 180
    }

    private var previewMaxHeight: CGFloat {
        isCodeContent ? 360 : 600
    }

    private var previewIdealHeight: CGFloat {
        let estimatedLineHeight: CGFloat = isCodeContent ? 20 : 22
        let verticalChrome: CGFloat = isCodeContent ? 42 : 56
        let estimated = CGFloat(min(previewLineCount, 18)) * estimatedLineHeight + verticalChrome
        return min(max(estimated, previewMinHeight), previewMaxHeight)
    }

    private var outerPadding: CGFloat {
        isCodeContent ? 12 : 16
    }

    var body: some View {
        NativeTextView(
            text: safeText,
            attributedText: highlightedAttr,
            style: isCodeContent ? .code : .plain
        )
            .frame(
                minWidth: previewMinWidth,
                idealWidth: previewIdealWidth,
                maxWidth: previewMaxWidth,
                minHeight: previewMinHeight,
                idealHeight: previewIdealHeight,
                maxHeight: previewMaxHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: isCodeContent ? 12 : 0, style: .continuous))
            .overlay {
                if isCodeContent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(outerPadding)
            .task(id: item.contentHash) {
                highlightedAttr = await ClipboardQuickLookTextLoader.loadHighlightedText(for: item)
            }
    }
}

@MainActor
private enum ClipboardQuickLookTextLoader {
    private static let rtfDecodeQueue = DispatchQueue(
        label: "clipaste.quicklook-rtf",
        qos: .userInitiated
    )

    static func loadHighlightedText(for item: ClipboardItem) async -> NSAttributedString? {
        guard item.hasRTF else {
            return nil
        }

        let rtfData = await StorageManager.shared.loadRTFData(id: item.id)
        guard let rtfData else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            rtfDecodeQueue.async {
                let attributedText = try? NSAttributedString(
                    data: rtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                continuation.resume(returning: attributedText)
            }
        }
    }
}
