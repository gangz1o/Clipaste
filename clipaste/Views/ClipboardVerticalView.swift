import SwiftUI

struct ClipboardVerticalView: View {
    let items: [ClipboardItem]
    let onSelect: (ClipboardItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    ClipboardCardView(item: item, onSelect: {
                        onSelect(item)
                    })
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .help("点击后粘贴到当前应用")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ClipboardVerticalView(items: [], onSelect: { _ in })
}
