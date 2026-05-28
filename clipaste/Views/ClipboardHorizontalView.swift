import SwiftUI

struct ClipboardHorizontalView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let items: [ClipboardItem]
    @FocusState var focusedField: ClipboardPanelFocusField?
    @AppStorage("requireCmdToDelete") private var requireCmdToDelete: Bool = false
    @State private var quickPasteIndexesByItemID: [UUID: Int] = [:]

    private let quickPasteCoordinateSpaceName = "ClipboardHorizontalQuickPasteSpace"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewportProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardCardView(
                                item: item,
                                viewModel: viewModel,
                                quickPasteIndex: quickPasteIndexesByItemID[item.id]
                            )
                                .id(item.id)
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .help("Click to paste to the active app")
                                .clipboardQuickPasteVisibleFrame(
                                    id: item.id,
                                    sourceIndex: index,
                                    coordinateSpaceName: quickPasteCoordinateSpaceName
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxHeight: .infinity, alignment: .center)
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
                    guard !requireCmdToDelete else { return }
                    guard !viewModel.selectedItemIDs.isEmpty else { return }
                    viewModel.batchDelete()
                }
                .onAppear {
                    scrollToPrimarySelection(with: proxy, animated: false)
                }
                .onChange(of: viewModel.listScrollRequest) { _, request in
                    guard let request else { return }
                    scrollToItem(
                        with: proxy,
                        itemID: request.id,
                        animated: request.animated
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func updateQuickPasteIndexes(
        frames: [ClipboardQuickPasteVisibleFrame],
        viewportSize: CGSize
    ) {
        let resolvedIndexes = ClipboardQuickPasteVisibleIndexResolver.resolve(
            frames: frames,
            viewportSize: viewportSize,
            axis: .horizontal,
            itemIDsInDisplayOrder: items.map(\.id)
        )

        guard resolvedIndexes != quickPasteIndexesByItemID else { return }
        quickPasteIndexesByItemID = resolvedIndexes
    }

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
    ClipboardHorizontalPreview()
}

private struct ClipboardHorizontalPreview: View {
    @FocusState private var focusedField: ClipboardPanelFocusField?

    var body: some View {
        ClipboardHorizontalView(
            viewModel: ClipboardViewModel(),
            items: [],
            focusedField: _focusedField
        )
    }
}
