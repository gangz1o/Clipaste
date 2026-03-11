import SwiftUI

struct ClipboardVerticalListView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredItems) { item in
                    ClipboardVerticalItemView(item: item, viewModel: viewModel)
                        .id(item.id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
        // 材质由 ClipboardMainView 最外层统一提供，此处不做局部 background
    }
}
