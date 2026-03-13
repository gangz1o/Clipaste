import SwiftUI

/// 精选 SF Symbols 网格选择器 — 用于新建/编辑分组时选择图标
struct GroupIconPicker: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) var dismiss

    private let icons = [
        "folder", "folder.fill", "doc.text", "terminal", "chevron.left.forwardslash.chevron.right",
        "paintpalette", "photo", "link", "globe", "envelope",
        "cart", "creditcard", "briefcase", "lock.shield", "key",
        "star", "heart", "bookmark", "flag", "bell",
        "tag", "tray", "archivebox", "shippingbox", "books.vertical"
    ]

    private let columns = [GridItem(.adaptive(minimum: 44))]

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose an Icon")
                .font(.headline)
                .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedIcon == icon ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(width: 280, height: 320)
        .padding(.bottom, 8)
    }
}

#Preview {
    GroupIconPicker(selectedIcon: .constant("folder"))
}
