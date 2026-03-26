import SwiftUI

struct ClipboardVerticalListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let items: [ClipboardItem]
    @FocusState var focusedField: ClipboardPanelFocusField?


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardVerticalItemView(
                            item: item,
                            viewModel: viewModel,
                            quickPasteIndex: index < 9 ? index : nil
                        )
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focusedField, equals: .clipList)
            .simultaneousGesture(TapGesture().onEnded {
                focusedField = .clipList
            })
            .onDeleteCommand {
                guard !viewModel.selectedItemIDs.isEmpty else { return }
                viewModel.batchDelete()
            }
            .onAppear {
                scrollToPrimarySelection(with: proxy)
            }
            .onChange(of: viewModel.selectedItemIDs) { _, _ in
                scrollToPrimarySelection(with: proxy)
            }
            .frame(maxHeight: .infinity)
        }
        // 材质由 ClipboardMainView 最外层统一提供，此处不做局部 background
    }

    private func scrollToPrimarySelection(with proxy: ScrollViewProxy) {
        guard let selectedID = viewModel.lastSelectedID ?? viewModel.selectedItemIDs.first else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(selectedID, anchor: .center)
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
