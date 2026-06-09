import SwiftUI

struct ClipboardVerticalListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let items: [ClipboardItem]
    @FocusState var focusedField: ClipboardPanelFocusField?
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("previewPanelMode") private var previewPanelMode: PreviewPanelMode = .disabled
    @AppStorage("autoPreview") private var autoPreview = true

    @State private var previewPanelViewModel = ClipboardPreviewPanelViewModel()
    @State private var quickPasteIndexesByItemID: [UUID: Int] = [:]

    // Layout constants
    private let previewAnimationDuration: Double = 0.3
    private let quickPasteCoordinateSpaceName = "ClipboardVerticalQuickPasteSpace"

    private var isCompact: Bool {
        clipboardLayout == .compact
    }

    private var isPreviewEnabled: Bool {
        previewPanelMode == .enabled
    }

    private var shouldAutoPreview: Bool {
        clipboardLayout == .vertical && isPreviewEnabled && autoPreview
    }

    private var shouldUseQuickLookAutoPreview: Bool {
        clipboardLayout == .vertical && autoPreview && !isPreviewEnabled
    }

    private var itemSpacing: CGFloat {
        isCompact ? 2 : 8
    }

    private var horizontalPadding: CGFloat {
        isCompact ? 4 : 12
    }

    private var verticalPadding: CGFloat {
        isCompact ? 6 : 12
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main list content
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Preview panel
            if isPreviewEnabled, let previewItem = previewPanelViewModel.selectedItem {
                ClipboardItemPreviewView(item: previewItem)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: previewAnimationDuration, dampingFraction: 0.85), value: previewPanelViewModel.selectedItem?.id)
        .onChange(of: viewModel.selectedItemIDs) { _, _ in
            previewPanelViewModel.handleSelectionChange(
                items: items,
                selectedItemIDs: viewModel.selectedItemIDs,
                isPreviewEnabled: shouldAutoPreview
            )
            viewModel.scheduleAutoPreviewForSelectionIfNeeded(
                isEnabled: shouldUseQuickLookAutoPreview
            )
        }
        .onChange(of: items) { _, _ in
            previewPanelViewModel.reconcile(
                items: items,
                selectedItemIDs: viewModel.selectedItemIDs,
                isPreviewEnabled: shouldAutoPreview
            )
        }
        .onChange(of: previewPanelMode) { _, _ in
            previewPanelViewModel.handlePreviewModeChange(
                items: items,
                selectedItemIDs: viewModel.selectedItemIDs,
                isPreviewEnabled: shouldAutoPreview
            )
            viewModel.presentAutoPreviewForSelectionIfNeeded(
                isEnabled: shouldUseQuickLookAutoPreview
            )
        }
        .onChange(of: autoPreview) { _, _ in
            previewPanelViewModel.handlePreviewModeChange(
                items: items,
                selectedItemIDs: viewModel.selectedItemIDs,
                isPreviewEnabled: shouldAutoPreview
            )
            viewModel.presentAutoPreviewForSelectionIfNeeded(
                isEnabled: shouldUseQuickLookAutoPreview
            )
        }
        .onAppear {
            previewPanelViewModel.handlePreviewModeChange(
                items: items,
                selectedItemIDs: viewModel.selectedItemIDs,
                isPreviewEnabled: shouldAutoPreview
            )
        }
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewportProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardVerticalItemView(
                                item: item,
                                viewModel: viewModel,
                                quickPasteIndex: quickPasteIndexesByItemID[item.id],
                                usesPreviewPanel: isPreviewEnabled,
                                allowsAutoPreview: clipboardLayout == .vertical,
                                onHoverChange: { isHovering in
                                    previewPanelViewModel.handleHoverChange(
                                        for: item,
                                        isHovering: isHovering,
                                        items: items,
                                        selectedItemIDs: viewModel.selectedItemIDs,
                                        isPreviewEnabled: shouldAutoPreview
                                    )
                                }
                            )
                                .id(item.id)
                                .clipboardQuickPasteVisibleFrame(
                                    id: item.id,
                                    sourceIndex: index,
                                    coordinateSpaceName: quickPasteCoordinateSpaceName
                                )
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
                .coordinateSpace(name: quickPasteCoordinateSpaceName)
                .onPreferenceChange(ClipboardQuickPasteVisibleFramePreferenceKey.self) { frames in
                    updateQuickPasteIndexes(
                        frames: frames,
                        viewportSize: viewportProxy.size
                    )
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focusedField, equals: .clipList)
                .simultaneousGesture(TapGesture().onEnded {
                    focusedField = .clipList
                })
                .onDeleteCommand {
                    viewModel.deleteSelection(isCommandHeld: false)
                }
                .onAppear {
                    scrollToPrimarySelection(with: proxy, animated: false)
                    previewPanelViewModel.handlePreviewModeChange(
                        items: items,
                        selectedItemIDs: viewModel.selectedItemIDs,
                        isPreviewEnabled: shouldAutoPreview
                    )
                }
                .onChange(of: viewModel.listScrollRequest) { _, request in
                    guard let request else { return }
                    scrollToItem(
                        with: proxy,
                        itemID: request.id,
                        animated: request.animated
                    )
                }
                .frame(maxHeight: .infinity)
            }
        }
        // 材质由 ClipboardMainView 最外层统一提供，此处不做局部 background
    }

    private func updateQuickPasteIndexes(
        frames: [ClipboardQuickPasteVisibleFrame],
        viewportSize: CGSize
    ) {
        let resolvedIndexes = ClipboardQuickPasteVisibleIndexResolver.resolve(
            frames: frames,
            viewportSize: viewportSize,
            axis: .vertical,
            itemIDsInDisplayOrder: items.map(\.id)
        )

        guard resolvedIndexes != quickPasteIndexesByItemID else { return }
        quickPasteIndexesByItemID = resolvedIndexes
    }

    // MARK: - Scroll Management

    private func scrollToPrimarySelection(with proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedID = viewModel.lastSelectedID ?? viewModel.selectedItemIDs.first else { return }
        scrollToItem(with: proxy, itemID: selectedID, animated: animated)
    }

    private func scrollToItem(with proxy: ScrollViewProxy, itemID: UUID, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            } else {
                proxy.scrollTo(itemID, anchor: .center)
            }
        }
    }
}

#Preview {
    ClipboardVerticalListPreview()
}

private struct ClipboardVerticalListPreview: View {
    @FocusState private var focusedField: ClipboardPanelFocusField?

    var body: some View {
        ClipboardVerticalListView(
            viewModel: ClipboardViewModel(),
            items: [],
            focusedField: _focusedField
        )
    }
}
