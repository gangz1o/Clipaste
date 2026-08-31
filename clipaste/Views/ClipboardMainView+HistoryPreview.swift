import SwiftUI


extension ClipboardMainView {
    var displayedItems: [ClipboardItem] {
        viewModel.displayedItems
    }

    var displayedItemIDs: [UUID] {
        viewModel.displayedItemIDs
    }

    @ViewBuilder
    var historyPreviewFooter: some View {
        HStack {
            Spacer()

            Text("\(displayedItems.count) Items")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .padding(.top, 4)
        .background(.regularMaterial)
    }
}
