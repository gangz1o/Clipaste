import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var onSelect: () -> Void = {}
    var viewModel: ClipboardViewModel? = nil
    @ObservedObject private var renderEngine = ListRenderEngine.shared

    @State private var isHovered = false

    private var isSelected: Bool {
        viewModel?.selectedItemIDs.contains(item.id) ?? false
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

                    // ── Material Type Badge ────────────────────────
                    TypeBadgeView(item: item, isCodeContent: isCodeContent)

                    // 时间 + 日期双行排版（弱化处理，不喧宾夺主）
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.timestamp.timeString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text(item.timestamp.dateString)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(minWidth: 44)
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
        // (Phase 1: 彩色边线已移除，由 Material Badge 取代)
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
        // ⚠️ 生命周期钩子：卡片首次出现时触发后台缓存
        .onAppear { renderEngine.prepareIfNeeded(for: item) }
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onDrag {
            viewModel?.draggedItemId = item.id
            return item.universalDragProvider
        } preview: {
            ClipboardDragPreview(item: item)
        }
        .modifier(ClipboardCardActionModifier(item: item, onSelect: onSelect, viewModel: viewModel))
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if item.contentType == .fileURL, let filePath = item.fileURL {
            // ── 文件类型：系统原生图标 + 文件名 + 路径 ──────────────────
            let resolvedPath: String = {
                if let url = URL(string: filePath), url.isFileURL {
                    return url.path
                }
                return filePath
            }()
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: resolvedPath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                VStack(spacing: 2) {
                    Text((resolvedPath as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                    Text(resolvedPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.contentType == .image {
            // ── 图片：等比例完整显示，绝不裁切原图 ──────────────────────
            ZStack {
                CheckerboardBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                ClipboardThumbnailView(itemID: item.id, maxPixelSize: 480) {
                    Group {
                        if item.hasImagePreview || item.hasImageData {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.secondary)
                        } else {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // ── 链接：Safari 风格地址栏样式 ────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                if let title = item.linkTitle, !title.isEmpty {
                    HighlightedText(text: title, highlight: searchHighlight,
                                    font: .system(size: 12, weight: .medium),
                                    highlightFont: .system(size: 12, weight: .bold))
                        .lineLimit(3)
                        .truncationMode(.tail)
                }

                // Safari-style URL bar
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(previewText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            // ── 普通文本（含代码）：▄▀ ListRenderEngine 缓存优先
            if let cached = renderEngine.cachedText(for: item.id) {
                Text(cached)
                    .lineSpacing(3)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
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
    }

    // MARK: - Helpers

    private var isCodeContent: Bool {
        item.contentType == .code || ["Xcode", "Terminal"].contains(item.appName)
    }
}

// MARK: - Material Type Badge

/// 毛玻璃微标签 — 极致通透的内容类型胶囊
private struct TypeBadgeView: View {
    let item: ClipboardItem
    let isCodeContent: Bool

    private var badgeIcon: String {
        switch item.contentType {
        case .image:    return "photo"
        case .fileURL:  return "doc.fill"
        case .link:     return "link"
        case .code:     return "curlybraces"
        case .color:    return "paintpalette.fill"
        case .text:
            if item.isFastLink { return "link" }
            if isCodeContent { return "curlybraces" }
            return "doc.text"
        }
    }

    private var badgeLabel: String {
        switch item.contentType {
        case .image:    return "图片"
        case .fileURL:  return "文件"
        case .link:     return "链接"
        case .code:     return "代码"
        case .color:    return "颜色"
        case .text:
            if item.isFastLink { return "链接" }
            if isCodeContent { return "代码" }
            return "文本"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: badgeIcon)
            Text(badgeLabel)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Checkerboard Background (for transparent images)

/// 经典灰白棋盘格 — 透明图片可视化底色
private struct CheckerboardBackground: View {
    let cellSize: CGFloat = 8
    let lightColor = Color.white.opacity(0.8)
    let darkColor = Color.gray.opacity(0.15)

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * cellSize,
                                      y: CGFloat(row) * cellSize,
                                      width: cellSize, height: cellSize)
                    context.fill(Path(rect), with: .color(isEven ? lightColor : darkColor))
                }
            }
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
