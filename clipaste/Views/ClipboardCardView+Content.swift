import AppKit
import SwiftUI


extension ClipboardCardView {
    var cardHeader: some View {
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

                Text(
                    item.timestamp,
                    format: .dateTime
                        .month(.twoDigits)
                        .day(.twoDigits)
                        .hour(.twoDigits(amPM: .omitted))
                        .minute(.twoDigits)
                )
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: true, vertical: false)
            .help(Text(item.timestamp, format: .dateTime.year().month().day().hour().minute()))
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBaseColor)
        .clipShape(headerShape)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            headerCustomTitleOverlay
        }
    }

    @ViewBuilder
    var bottomAccessory: some View {
        if let quickPasteNumber, showsQuickPasteBadge {
            QuickPasteShortcutBadge(
                modifierKey: viewModel.quickPasteModifier,
                number: quickPasteNumber,
                color: .secondary
            )
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .transition(.opacity)
        } else if showsAIShortcut {
            ClipboardAIActionMenu(item: item, viewModel: viewModel) {
                ClipboardAIBadgeView(size: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("AI"))
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: - Content Body

    @ViewBuilder
    var contentBody: some View {
        if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
            let displayPath = item.fileDisplayPath ?? fileURL.path

            if item.fileRepresentsImage {
                ZStack {
                    ClipboardCardCheckerboardBackground()
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
                ClipboardCardCheckerboardBackground()
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
            switch viewModel.settingsViewModel.linkDisplayMode {
            case .rich:
                ClipboardLinkPreviewCardView(
                    viewModel: ClipboardLinkPreviewViewModel(item: item),
                    highlight: searchHighlight
                )
            case .plain:
                ClipboardLinkPlainCardView(
                    viewModel: ClipboardLinkPreviewViewModel(item: item),
                    highlight: searchHighlight
                )
            }
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

    var isCodeContent: Bool {
        item.contentType == .code
    }

    var showsAIShortcut: Bool {
        viewModel.aiSettingsViewModel.isAIEnabled
            && (isHovered || isSelected)
            && viewModel.isQuickPasteModifierHeld == false
    }

    var showsFavoriteShortcut: Bool {
        (isHovered || isSelected)
            && viewModel.isQuickPasteModifierHeld == false
    }

    var isScreenPinDragActive: Bool {
        screenPinViewModel.isEnabled && item.isScreenPinEligible
    }

    func toggleFavorite() {
        if singleClickPaste {
            viewModel.handlePrimaryClickSelection(for: item.id)
        }
        viewModel.suppressNextPaste(for: item.id)
        viewModel.pinItem(item: item)
    }

    @ViewBuilder
    var headerCustomTitleOverlay: some View {
        if item.hasCustomTitle {
            VStack {
                Spacer(minLength: 0)

                ClipboardItemCustomTitleView(
                    item: item,
                    viewModel: viewModel,
                    font: .system(size: 11, weight: .semibold),
                    textColor: .white.opacity(0.96)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, headerHeight + 10)
            .padding(.trailing, 76)
            .padding(.bottom, 8)
        }
    }

    @MainActor
    func refreshRichPreviewText() async {
        richPreviewText = ListRenderEngine.shared.cachedText(for: item.id)

        guard richPreviewText == nil else {
            return
        }

        richPreviewText = await ListRenderEngine.shared.prepareText(for: item)
    }
}

// MARK: - Checkerboard Background (for transparent images)

/// 经典灰白棋盘格 — 透明图片可视化底色
private struct ClipboardCardCheckerboardBackground: View {
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
