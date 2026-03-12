import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var onSelect: () -> Void = {}
    var viewModel: ClipboardViewModel? = nil

    @State private var isHovered = false

    private var isSelected: Bool {
        viewModel?.highlightedItemId == item.id
    }

    private var previewText: String {
        if let rawText = item.rawText, !rawText.isEmpty { return rawText }
        return item.textPreview.isEmpty ? "（空）" : item.textPreview
    }

    private var searchHighlight: String { viewModel?.searchText ?? "" }

    // MARK: - Body
    var body: some View {
        ZStack {
            // ── 水印层：App 图标，最底层──────────────────────────────────
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .saturation(0)
                    .opacity(0.06)
                    .blur(radius: 5)
                    .offset(x: 30, y: 30)
                    .clipped()
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 0) {
                // ── Header：App 图标 + 名称 + 时间 ─────────────────────────
                HStack(alignment: .center, spacing: 8) {
                    Group {
                        if let icon = item.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)

                    Text(item.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // 链接角标
                    if previewText.lowercased().hasPrefix("http") {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    } else if item.contentType == .image {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(item.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

                // ── Body：内容区域 ─────────────────────────────────────────
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        // 横版大卡片固定尺寸
        .frame(width: 240, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .windowBackgroundColor).opacity(0.5)
                )
        )
        .background(
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(alignment: .leading) {
            // 类型颜色条
            Rectangle()
                .fill(typeAccentColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        // 空格键 QuickLook 气泡（箭头朝下，挂在卡片顶部）
        .popover(
            isPresented: Binding(
                get: { viewModel?.quickLookItem?.id == item.id },
                set: { isShowing in
                    if !isShowing, viewModel?.quickLookItem?.id == item.id {
                        viewModel?.quickLookItem = nil
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            ClipboardQuickLookView(item: item)
        }
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            ClipboardDragPreview(item: item)
        }
        .modifier(ClipboardCardActionModifier(item: item, onSelect: onSelect, viewModel: viewModel))
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if item.contentType == .image {
            // ── 图片：等比例完整显示，绝不裁切原图 ──────────────────────
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        ZStack {
                            // 底层垫一层极其微弱的背景，让透明 PNG 也能优雅展示
                            Color(nsColor: .controlBackgroundColor).opacity(0.5)
                            img.resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .cornerRadius(8)
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        } else if let parsedColor = ColorParser.extractColor(from: previewText) {
            // ── 颜色块：全卡片沉浸式填充 ──────────────────────────────────
            ZStack {
                parsedColor
                Text(previewText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(parsedColor.isDark ? .white : .black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(8)
        } else if previewText.lowercased().hasPrefix("http") {
            // ── 链接：标题优先书签（无图标）────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                if let title = item.linkTitle, !title.isEmpty {
                    HighlightedText(text: title, highlight: searchHighlight,
                                    font: .system(size: 12, weight: .medium),
                                    highlightFont: .system(size: 12, weight: .bold))
                        .lineLimit(3)
                        .truncationMode(.tail)
                    Text(previewText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    HighlightedText(text: previewText, highlight: searchHighlight,
                                    font: .system(size: 12),
                                    foregroundColor: .blue.opacity(0.85),
                                    highlightFont: .system(size: 12, weight: .bold))
                        .lineLimit(6)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            // ── 普通文本（含代码）────────────────────────────────────────
            HighlightedText(
                text: previewText,
                highlight: searchHighlight,
                font: .system(size: 12, design: isCodeContent ? .monospaced : .default),
                foregroundColor: .primary.opacity(0.85),
                highlightFont: .system(size: 12, weight: .bold, design: isCodeContent ? .monospaced : .default)
            )
            .lineSpacing(3)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Helpers

    private var isCodeContent: Bool {
        ["Xcode", "Terminal"].contains(item.appName)
    }

    private var typeAccentColor: Color {
        switch item.contentType {
        case .image: return .purple
        case .fileURL: return .orange
        default:
            if previewText.lowercased().hasPrefix("http") { return .orange }
            if isCodeContent { return .blue }
            return .green
        }
    }
}

#Preview {
    ClipboardCardView(
        item: ClipboardItem(
            contentType: .text,
            contentHash: CryptoHelper.generateHash(
                for: "Preview text of the copied content goes here. It might be long and should truncate."),
            textPreview: "Preview text of the copied content goes here. It might be long and should truncate.",
            appName: "Safari",
            appIconName: "safari",
            rawText: "Preview text of the copied content goes here. It might be long and should truncate."
        )
    )
    .padding()
    .background(Color.black)
}
