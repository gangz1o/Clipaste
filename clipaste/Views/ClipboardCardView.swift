import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    var quickPasteIndex: Int? = nil

    @State private var isHovered = false
    @State private var richPreviewText: AttributedString?
    @State private var appIconDominantColorHex: String?

    private var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }

    private var previewText: String {
        if let preview = item.previewText, !preview.isEmpty { return preview }
        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    private var searchHighlight: String { viewModel.activeSearchQuery }

    private var quickPasteNumber: Int? {
        quickPasteIndex.map { $0 + 1 }
    }

    private var showsQuickPasteBadge: Bool {
        quickPasteNumber != nil && viewModel.isQuickPasteModifierHeld
    }

    private var richTextTaskKey: String {
        "\(item.id.uuidString)-\(item.contentHash)-\(item.hasRTF)"
    }

    private var headerColorTaskKey: String {
        "\(item.id.uuidString)-\(item.contentHash)-\(item.timestamp.timeIntervalSince1970)"
    }

    private var headerBaseColor: Color {
        if let storedColor = Color(clipasteHex: appIconDominantColorHex) {
            return storedColor
        }

        if let iconColorHex = resolvedAppIcon?.dominantColorHex(),
           let iconColor = Color(clipasteHex: iconColorHex) {
            return iconColor
        }

        return Color(nsColor: .darkGray)
    }

    private var headerTimestampText: String {
        "\(item.timestamp.dateString) \(item.timestamp.timeString)"
    }

    private var headerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 16,
            style: .continuous
        )
    }

    private var headerHeight: CGFloat {
        52
    }

    private var resolvedAppIcon: NSImage? {
        if let icon = item.appIcon {
            return icon
        }

        guard let bundleIdentifier = item.sourceBundleIdentifier else {
            return nil
        }

        return AppIconManager.shared.getIcon(for: bundleIdentifier)
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            ZStack {
                Color(nsColor: .textBackgroundColor)

                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 240, height: 240)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            if let quickPasteIndex {
                QuickPasteShortcutHost(
                    shortcutIndex: quickPasteIndex,
                    modifierKey: viewModel.quickPasteModifier
                ) {
                    viewModel.pasteToActiveApp(item: item)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let quickPasteNumber, showsQuickPasteBadge {
                QuickPasteShortcutBadge(
                    modifierKey: viewModel.quickPasteModifier,
                    number: quickPasteNumber,
                    color: .secondary
                )
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.48) : Color.black.opacity(0.08),
                    lineWidth: isSelected ? 1.4 : 0.8
                )
        }
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.15), value: showsQuickPasteBadge)
        // 空格键 QuickLook 气泡（箭头朝下，挂在卡片顶部）
        .popover(
            isPresented: Binding(
                get: { viewModel.quickLookItem?.id == item.id },
                set: { isShowing in
                    if !isShowing, viewModel.quickLookItem?.id == item.id {
                        viewModel.dismissQuickLook()
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            ClipboardQuickLookView(item: item, viewModel: viewModel)
        }
        // 分享锚点：用 background 捕获 NSView + onChange 触发分享
        .modifier(OptionalShareModifier(item: item, viewModel: viewModel))
        .task(id: richTextTaskKey) {
            await refreshRichPreviewText()
        }
        .task(id: headerColorTaskKey) {
            await refreshHeaderDominantColorHex()
        }
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onDrag {
            viewModel.draggedItemId = item.id
            return item.universalDragProvider
        } preview: {
            ClipboardDragPreview(item: item)
        }
        .modifier(ClipboardCardActionModifier(item: item, viewModel: viewModel))
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            AppIconView(appBundleID: item.sourceBundleIdentifier, size: headerHeight)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.typeBadgeTitle())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(headerTimestampText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: true, vertical: false)
            .help(item.timestamp.formatted(date: .complete, time: .standard))
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBaseColor)
        .clipShape(headerShape)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
            let displayPath = item.fileDisplayPath ?? fileURL.path

            if item.fileRepresentsImage {
                ZStack {
                    CheckerboardBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    ClipboardFileThumbnailView(fileURL: fileURL, maxPixelSize: 480) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // ── 文件类型：系统原生图标 + 文件名 + 路径 ──────────────────
                VStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                    VStack(spacing: 2) {
                        Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.center)
                        Text(displayPath)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            if let richPreviewText {
                Text(richPreviewText)
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
        item.contentType == .code
    }

    @MainActor
    private func refreshHeaderDominantColorHex() {
        appIconDominantColorHex = StorageManager.shared
            .fetchRecord(id: item.id)?
            .appIconDominantColorHex
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

private extension Color {
    init?(clipasteHex hex: String?) {
        guard let hex else { return nil }

        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return nil
        }

        self = Color(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
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
        ),
        viewModel: ClipboardViewModel()
    )
    .padding()
    .background(Color.black)
}
