import SwiftUI

struct ClipboardHorizontalView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let items: [ClipboardItem]
    @FocusState var focusedField: ClipboardPanelFocusField?


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardCardView(
                            item: item,
                            viewModel: viewModel,
                            quickPasteIndex: index < 9 ? index : nil
                        )
                            .id(item.id)
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                            .help("Click to paste to the active app")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity, alignment: .center)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
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
