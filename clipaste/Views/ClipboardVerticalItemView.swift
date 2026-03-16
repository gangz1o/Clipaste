import SwiftUI

struct ClipboardVerticalItemView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    @ObservedObject private var renderEngine = ListRenderEngine.shared

    @State private var isHovering = false

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

    var body: some View {
        HStack(spacing: 12) {
            // 1. 左侧：App 图标
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
            } else {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Image(systemName: "app.dashed").foregroundColor(.secondary)
                }
                .frame(width: 32, height: 32)
            }

            // 2. 中间：内容预览
            VStack(alignment: .leading, spacing: 4) {
                if item.contentType == .fileURL, let filePath = item.fileURL {
                    // ── 文件类型：系统原生图标 + 文件名 + 路径 ──────────────
                    let resolvedPath: String = {
                        if let url = URL(string: filePath), url.isFileURL {
                            return url.path
                        }
                        return filePath
                    }()
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: resolvedPath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((resolvedPath as NSString).lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(resolvedPath)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if item.contentType == .image {
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
                    if parsedColor != nil {
                        // 颜色条目：只居中展示等宽色值，背景由卡片层处理
                        Text(previewText)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
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
                        // ⚠️ 渲染核心：ListRenderEngine 缓存优先
                        // 缓存命中 → 0 延迟渲染高亮文本
                        // 缓存未命中 → 瞬间使用纯文本垫底 + onAppear 触发后台缓存
                        if let cached = renderEngine.cachedText(for: item.id) {
                            Text(cached)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            HighlightedText(text: previewText, highlight: viewModel.activeSearchQuery)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. 右侧：时间 + 日期双行排版（弱化处理）
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.timestamp.timeString)
                    .font(.system(size: 11))
                    .foregroundColor(
                        parsedColor.map { $0.isDark ? .white.opacity(0.6) : .black.opacity(0.45) }
                        ?? .secondary
                    )

                Text(item.timestamp.dateString)
                    .font(.system(size: 9))
                    .foregroundColor(
                        parsedColor.map { $0.isDark ? .white.opacity(0.4) : .black.opacity(0.3) }
                        ?? .secondary.opacity(0.7)
                    )
            }
            .help(item.timestamp.formatted(date: .complete, time: .standard))
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    // 颜色卡片：整行用解析出的颜色填充；否则沿用默认选中/悬停样式
                    parsedColor.map { AnyShapeStyle($0) }
                    ?? AnyShapeStyle(
                        isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1.0 : 0.6)
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    parsedColor != nil
                        ? Color.primary.opacity(0.12)   // 颜色卡片用极细中性描边
                        : (isSelected ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.45) : Color.clear)),
                    lineWidth: (parsedColor != nil || isSelected) ? 1.5 : 1.5
                )
        )
        // ⚠️ 生命周期钩子：卡片首次出现时触发后台缓存
        .onAppear { renderEngine.prepareIfNeeded(for: item) }
        // 分享锚点：用 background 捕获 NSView + onChange 触发分享
        .shareable(item: item, viewModel: viewModel)
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
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
                        viewModel.quickLookItem = nil
                    }
                }
            ),
            arrowEdge: .trailing  // 气泡在卡片左侧弹出，箭头指向卡片
        ) {
            ClipboardQuickLookView(item: item)
        }
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
            } else if item.contentType == .fileURL, let filePath = item.fileURL {
                // File type: show native file icon
                let resolvedPath: String = {
                    if let url = URL(string: filePath), url.isFileURL { return url.path }
                    return filePath
                }()
                Image(nsImage: NSWorkspace.shared.icon(forFile: resolvedPath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else if item.isFastLink {
                // Link type: link badge
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
            } else if let icon = item.appIcon {
                // Has source app: show its icon
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else {
                // Plain text / fallback
                Image(systemName: "doc.text.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 36)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 64, height: 64)
    }
}
