import SwiftUI

struct ClipboardVerticalItemView: View {
    private enum Layout {
        static let rowHorizontalPadding: CGFloat = 12
        static let appIconSize: CGFloat = 42
        static let contentSpacing: CGFloat = 12
        static let compactAppIconSize: CGFloat = 28
        static let customTitleWidth: CGFloat = 92
        static let customTitleHeight: CGFloat = 13
        static let customTitleLeading: CGFloat = rowHorizontalPadding + appIconSize + contentSpacing
        static let customTitleTop: CGFloat = 8
    }

    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    let quickPasteIndex: Int?
    let onHoverChange: ((Bool) -> Void)?

    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal

    @State private var isHovering = false
    @State private var richPreviewText: AttributedString?

    private var isCompact: Bool {
        clipboardLayout == .compact
    }

    private var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }

    /// 颜色嗅探结果：使用极速短路版本，超过 100 字符跳过正则
    private var parsedColor: Color? {
        item.fastParsedColor
    }

    private var previewText: String {
        if let preview = item.previewText, !preview.isEmpty {
            return preview
        }

        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    private var quickPasteNumber: Int? {
        quickPasteIndex.map { $0 + 1 }
    }

    private var showsQuickPasteBadge: Bool {
        quickPasteNumber != nil && viewModel.isQuickPasteModifierHeld
    }

    private var richTextTaskKey: String {
        "\(item.id.uuidString)-\(item.contentHash)-\(item.hasRTF)"
    }

    private var rowFillStyle: AnyShapeStyle {
        if let parsedColor {
            return AnyShapeStyle(parsedColor)
        }

        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }

        return AnyShapeStyle(
            Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1.0 : 0.6)
        )
    }

    private var rowBorderColor: Color {
        if parsedColor != nil {
            return Color.primary.opacity(0.12)
        }

        if isSelected {
            return Color.accentColor
        }

        if isHovering {
            return Color.accentColor.opacity(0.45)
        }

        return .clear
    }

    private var timeTextColor: Color {
        parsedColor.map { $0.isDark ? .white.opacity(0.6) : .black.opacity(0.45) }
            ?? .secondary
    }

    private var dateTextColor: Color {
        parsedColor.map { $0.isDark ? .white.opacity(0.4) : .black.opacity(0.3) }
            ?? .secondary.opacity(0.7)
    }

    private var customTitleTextColor: Color {
        parsedColor.map { $0.isDark ? .white.opacity(0.96) : .black.opacity(0.9) }
        ?? .black.opacity(0.9)
    }

    var body: some View {
        rowContent
            .padding(.horizontal, isCompact ? 6 : Layout.rowHorizontalPadding)
            .frame(height: isCompact ? 36 : 76)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 6 : 12)
                    .fill(rowFillStyle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 6 : 12)
                    .stroke(rowBorderColor, lineWidth: isCompact ? 1.0 : 1.5)
            )
            .overlay(alignment: .topLeading) {
                customTitleOverlay
            }
            .task(id: richTextTaskKey) {
                await refreshRichPreviewText()
            }
            .background { quickPasteShortcutBackground }
            // 分享锚点：用 background 捕获 NSView + onChange 触发分享
            .shareable(item: item, viewModel: viewModel)
            .clipboardContextMenu(for: item, viewModel: viewModel)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
                onHoverChange?(hovering)
            }
            .animation(.easeInOut(duration: 0.15), value: showsQuickPasteBadge)
            .onDrag {
                viewModel.draggedItemId = item.id
                return item.universalDragProvider
            } preview: {
                ClipboardDragPreview(item: item)
            }
            .clipboardItemActions(for: item, viewModel: viewModel)
            // 空格键 QuickLook：以本卡片为锚点弹出原生气泡预览
            .popover(
                isPresented: Binding(
                    get: { viewModel.quickLookItem?.id == item.id },
                    set: { isShowing in
                        if !isShowing, viewModel.quickLookItem?.id == item.id {
                            viewModel.dismissQuickLook()
                        }
                    }
                ),
                arrowEdge: .trailing  // 气泡在卡片左侧弹出，箭头指向卡片
            ) {
                ClipboardQuickLookView(item: item, viewModel: viewModel)
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: isCompact ? 6 : Layout.contentSpacing) {
            // 1. 左侧：App 图标
            AppIconView(appBundleID: item.sourceBundleIdentifier, size: isCompact ? Layout.compactAppIconSize : Layout.appIconSize)
                .shadow(color: Color.black.opacity(0.1), radius: isCompact ? 1 : 2, y: isCompact ? 1 : 1)

            // 2. 中间：内容预览
            VStack(alignment: .leading, spacing: isCompact ? 0 : 4) {
                if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
                    let displayPath = item.fileDisplayPath ?? fileURL.path

                    if item.fileRepresentsImage {
                        if !isCompact {
                            ClipboardFileThumbnailView(fileURL: fileURL, maxPixelSize: 160) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                            }
                            .frame(maxHeight: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            // Compact: just show file name
                            Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        // ── 文件类型：系统原生图标 + 文件名 + 路径 ──────────────
                        if !isCompact {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(displayPath)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Compact: just show file name
                            Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else if item.contentType == .image {
                    if !isCompact {
                        ClipboardThumbnailView(itemID: item.id, maxPixelSize: 160) {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                                .frame(height: 44)
                        }
                        .frame(maxHeight: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // Compact: just show image indicator
                        Text("Image")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    if parsedColor != nil {
                        // 颜色条目：只居中展示等宽色值，背景由卡片层处理
                        Text(previewText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(parsedColor!.isDark ? .white : .black)
                            .shadow(
                                color: parsedColor!.isDark
                                    ? Color.black.opacity(0.3)
                                    : Color.white.opacity(0.3),
                                radius: 1, x: 0, y: 1
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if item.isFastLink {
                        // 链接 — 标题优先的书签样式
                        if !isCompact {
                            VStack(alignment: .leading, spacing: 2) {
                                if let title = item.linkTitle, !title.isEmpty {
                                    HighlightedText(text: title, highlight: viewModel.activeSearchQuery)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(previewText)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                } else {
                                    HighlightedText(text: previewText, highlight: viewModel.activeSearchQuery)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .foregroundColor(.blue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Compact: single line with title or URL
                            if let title = item.linkTitle, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text(previewText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    } else {
                        // ⚠️ 渲染核心：ListRenderEngine 缓存优先
                        // 缓存命中 → 0 延迟渲染高亮文本
                        // 缓存未命中 → 瞬间使用纯文本垫底 + onAppear 触发后台缓存
                        if let richPreviewText {
                            Text(richPreviewText)
                                .lineLimit(isCompact ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        } else {
                            HighlightedText(text: previewText, highlight: viewModel.activeSearchQuery)
                                .lineLimit(isCompact ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. 右侧：时间 + 日期双行排版（弱化处理）
            if !isCompact {
                VStack(alignment: .trailing, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.timestamp.timeString)
                            .font(.system(size: 11))
                            .foregroundColor(timeTextColor)

                        Text(item.timestamp.dateString)
                            .font(.system(size: 9))
                            .foregroundColor(dateTextColor)
                    }

                    Spacer(minLength: 4)

                    quickPasteInlineLabel
                }
                .padding(.top, 4)
                .help(item.timestamp.formatted(date: .complete, time: .standard))
                .frame(minWidth: 44, maxHeight: .infinity, alignment: .topTrailing)
            } else {
                // Compact: just show time on the right
                Text(item.timestamp.timeString)
                    .font(.system(size: 10))
                    .foregroundColor(timeTextColor)
                    .help(item.timestamp.formatted(date: .complete, time: .standard))
            }
        }
    }

    @ViewBuilder
    private var quickPasteShortcutBackground: some View {
        if let quickPasteIndex {
            QuickPasteShortcutHost(
                shortcutIndex: quickPasteIndex,
                modifierKey: viewModel.quickPasteModifier
            ) {
                viewModel.pasteToActiveApp(item: item)
            }
        }
    }

    @ViewBuilder
    private var quickPasteInlineLabel: some View {
        if let quickPasteNumber, showsQuickPasteBadge {
            QuickPasteShortcutBadge(
                modifierKey: viewModel.quickPasteModifier,
                number: quickPasteNumber,
                color: timeTextColor
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var customTitleOverlay: some View {
        if item.hasCustomTitle && !isCompact {
            ClipboardItemCustomTitleView(
                item: item,
                viewModel: viewModel,
                font: .system(size: 11, weight: .semibold),
                textColor: customTitleTextColor
            )
            .frame(
                width: Layout.customTitleWidth,
                height: Layout.customTitleHeight,
                alignment: .topLeading
            )
            .clipped()
            .padding(.leading, Layout.customTitleLeading)
            .padding(.top, Layout.customTitleTop)
        }
    }

    @MainActor
    private func refreshRichPreviewText() async {
        richPreviewText = ListRenderEngine.shared.cachedText(for: item.id)

        guard richPreviewText == nil else {
            return
        }

        richPreviewText = await ListRenderEngine.shared.prepareText(for: item)
    }
}

// MARK: - Drag Preview

struct ClipboardDragPreview: View {
    let item: ClipboardItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)

            if item.contentType == .image {
                ClipboardThumbnailView(itemID: item.id, maxPixelSize: 120) {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
                // File type: show native file icon
                let displayPath = item.fileDisplayPath ?? fileURL.path
                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else if item.isFastLink {
                // Link type: link badge
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
            } else {
                AppIconView(appBundleID: item.sourceBundleIdentifier, size: 36)
            }
        }
        .frame(width: 64, height: 64)
    }
}
