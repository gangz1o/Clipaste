import SwiftUI

struct ClipboardVerticalItemView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    @State private var isHovering = false

    private var isSelected: Bool {
        viewModel.highlightedItemId == item.id
    }

    /// 颜色嗅探结果：非 nil 时整张卡片用该颜色渲染
    private var parsedColor: Color? {
        ColorParser.extractColor(from: previewText)
    }

    private var previewText: String {
        if let rawText = item.rawText, !rawText.isEmpty {
            return rawText
        }

        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    var body: some View {
        HStack(spacing: 14) {
            // 1. 左侧：App 图标
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
            } else {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Image(systemName: "app.dashed").foregroundColor(.secondary)
                }
                .frame(width: 36, height: 36)
            }

            // 2. 中间：内容预览
            VStack(alignment: .leading, spacing: 4) {
                if item.contentType == .image, let url = item.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 40)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 40)
                        }
                    }
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
                    } else if previewText.lowercased().hasPrefix("http") {
                        // 链接 — 标题优先的书签样式
                        VStack(alignment: .leading, spacing: 2) {
                            if let title = item.linkTitle, !title.isEmpty {
                                HighlightedText(text: title, highlight: viewModel.searchText)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(previewText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                HighlightedText(text: previewText, highlight: viewModel.searchText)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // 普通文本兜底
                        HighlightedText(text: previewText, highlight: viewModel.searchText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. 右侧：时间
            VStack(alignment: .trailing, spacing: 10) {
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    // 颜色卡片时，时间文字也跟着反转，保证可读性
                    .foregroundColor(
                        parsedColor.map { $0.isDark ? .white.opacity(0.8) : .black.opacity(0.6) }
                        ?? .secondary
                    )

                Spacer().frame(height: 12)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
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
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
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

            if item.contentType == .image, let url = item.thumbnailURL,
               let img = NSImage(contentsOf: url) {
                // Image type: show actual thumbnail
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if item.rawText?.lowercased().hasPrefix("http") == true {
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
