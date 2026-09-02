import SwiftUI

struct ClipboardVerticalItemView: View {
    enum Layout {
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
    var viewModel: ClipboardViewModel
    let quickPasteIndex: Int?
    let usesPreviewPanel: Bool
    let allowsAutoPreview: Bool
    let onHoverChange: ((Bool) -> Void)?

    @Environment(ScreenPinViewModel.self) var screenPinViewModel
    @AppStorage("clipboardLayout") var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appAccentColor") var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("singleClickPaste") var singleClickPaste = false
    @AppStorage("autoPreview") var autoPreview = true

    @State var isHovering = false
    @State var richPreviewText: AttributedString?

    var isCompact: Bool {
        clipboardLayout == .compact
    }

    var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }

    /// 颜色嗅探结果：使用极速短路版本，超过 100 字符跳过正则
    var parsedColor: Color? {
        item.fastParsedColor
    }

    var previewText: String {
        if let preview = item.previewText, !preview.isEmpty {
            return preview
        }

        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    var quickPasteNumber: Int? {
        quickPasteIndex.map { $0 + 1 }
    }

    var showsQuickPasteBadge: Bool {
        quickPasteNumber != nil && viewModel.isQuickPasteModifierHeld
    }

    var richTextTaskKey: String {
        "\(item.id.uuidString)-\(item.contentHash)-\(item.hasRTF)"
    }

    var rowFillStyle: AnyShapeStyle {
        if let parsedColor {
            return AnyShapeStyle(parsedColor)
        }

        if isSelected {
            return AnyShapeStyle(appAccentColor.color.opacity(0.12))
        }

        return AnyShapeStyle(
            Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1.0 : 0.6)
        )
    }

    var rowBorderColor: Color {
        if parsedColor != nil {
            return Color.primary.opacity(0.12)
        }

        if isSelected {
            return appAccentColor.color
        }

        if isHovering {
            return appAccentColor.color.opacity(0.45)
        }

        return .clear
    }

    var timeTextColor: Color {
        parsedColor.map { $0.isDark ? .white.opacity(0.6) : .black.opacity(0.45) }
            ?? .secondary
    }

    var dateTextColor: Color {
        parsedColor.map { $0.isDark ? .white.opacity(0.4) : .black.opacity(0.3) }
            ?? .secondary.opacity(0.7)
    }

    var customTitleTextColor: Color {
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
            // 分享锚点：用 background 捕获 NSView + onChange 触发分享
            .shareable(item: item, viewModel: viewModel)
            .clipboardContextMenu(for: item, viewModel: viewModel)
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
            .overlay(alignment: .leading) {
                ScreenPinIconDragTarget(isActive: isScreenPinDragActive) { screenPoint in
                    screenPinViewModel.createPin(for: item, at: screenPoint)
                }
                .frame(
                    width: isCompact ? Layout.compactAppIconSize : Layout.appIconSize,
                    height: isCompact ? Layout.compactAppIconSize : Layout.appIconSize
                )
                .padding(.leading, isCompact ? 6 : Layout.rowHorizontalPadding)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
                onHoverChange?(hovering)
                viewModel.handleAutoPreviewHover(
                    for: item,
                    isHovering: hovering,
                    isEnabled: allowsAutoPreview && autoPreview && !usesPreviewPanel
                )
            }
    }

}
