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
        if let preview = item.previewText, !preview.isEmpty { return preview }
        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    private var searchHighlight: String { viewModel?.activeSearchQuery ?? "" }

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
                    .frame(width: 32, height: 32)

                    Text(item.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // 链接角标
                    if item.isFastLink {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    } else if item.contentType == .image {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // 智能时间：非今天显示日期前缀
                    HStack(spacing: 3) {
                        if !Calendar.current.isDateInToday(item.timestamp) {
                            Text(item.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        }
                        Text(item.timestamp, format: .dateTime.hour().minute())
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .help(item.timestamp.formatted(date: .complete, time: .standard))
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
        // 分享锚点：用 background 捕获 NSView + onChange 触发分享
        .modifier(OptionalShareModifier(item: item, viewModel: viewModel))
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onDrag {
            item.universalDragProvider
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
                        img.resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        } else if let parsedColor = item.fastParsedColor {
            // ── 颜色块：全卡片沉浸式填充 ──────────────────────────────────
            ZStack {
                parsedColor
                Text(previewText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(parsedColor.isDark ? .white : .black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(8)
        } else if item.isFastLink {
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
            if item.isFastLink { return .orange }
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
