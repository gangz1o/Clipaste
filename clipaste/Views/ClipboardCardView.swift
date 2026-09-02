import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var viewModel: ClipboardViewModel
    var quickPasteIndex: Int? = nil

    @Environment(ScreenPinViewModel.self) var screenPinViewModel
    @State var isHovered = false
    @State var richPreviewText: AttributedString?
    @AppStorage("appAccentColor") var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("autoPreview") var autoPreview = true
    @AppStorage("singleClickPaste") var singleClickPaste = false

    var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }

    var previewText: String {
        if let preview = item.previewText, !preview.isEmpty { return preview }
        return item.textPreview.isEmpty ? String(localized: "(Empty)") : item.textPreview
    }

    var searchHighlight: String { viewModel.activeSearchQuery }

    var quickPasteNumber: Int? {
        quickPasteIndex.map { $0 + 1 }
    }

    var showsQuickPasteBadge: Bool {
        quickPasteNumber != nil && viewModel.isQuickPasteModifierHeld
    }

    var richTextTaskKey: String {
        "\(item.id.uuidString)-\(item.contentHash)-\(item.hasRTF)"
    }

    var headerBaseColor: Color {
        if let storedColor = Color(clipasteHex: item.appIconDominantColorHex) {
            return storedColor
        }
        return Color(nsColor: .darkGray)
    }

    var headerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 16,
            style: .continuous
        )
    }

    var headerHeight: CGFloat {
        52
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
        .overlay(alignment: .bottomTrailing) {
            bottomAccessory
        }
        .overlay(alignment: .bottomLeading) {
            if showsFavoriteShortcut {
                ClipboardFavoriteButton(
                    isFavorite: item.isPinned,
                    accentColor: appAccentColor.color,
                    action: toggleFavorite
                )
                .padding(.leading, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? appAccentColor.color.opacity(0.95) : Color.black.opacity(0.08),
                    lineWidth: isSelected ? 6 : 0.8
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
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onDrag {
            viewModel.draggedItemId = item.id
            return item.universalDragProvider
        } preview: {
            ClipboardDragPreview(item: item)
        }
        .overlay(alignment: .topLeading) {
            ScreenPinIconDragTarget(isActive: isScreenPinDragActive) { screenPoint in
                screenPinViewModel.createPin(for: item, at: screenPoint)
            }
            .frame(width: headerHeight, height: headerHeight)
            .padding(.leading, 8)
        }
        .onHover { hovering in
            isHovered = hovering
            viewModel.handleAutoPreviewHover(
                for: item,
                isHovering: hovering,
                isEnabled: autoPreview
            )
        }
        .modifier(ClipboardCardActionModifier(item: item, viewModel: viewModel))
    }

}

extension Color {
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
