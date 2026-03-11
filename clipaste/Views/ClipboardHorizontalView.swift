import SwiftUI

struct ClipboardHorizontalView: View {
    let items: [ClipboardItem]
    let onSelect: (ClipboardItem) -> Void
    var viewModel: ClipboardViewModel? = nil

    @State private var hoveredItemID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(items) { item in
                    ClipboardCardView(item: item, onSelect: {
                        onSelect(item)
                    }, viewModel: viewModel)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    hoveredItemID == item.id ? Color.accentColor.opacity(0.45) : .clear,
                                    lineWidth: 1.5
                                )
                        )
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.18)) {
                                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                            }
                        }
                        .help("点击后粘贴到当前应用")
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    ClipboardHorizontalView(items: [], onSelect: { _ in })
}
