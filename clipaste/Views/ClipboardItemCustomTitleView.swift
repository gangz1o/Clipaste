import SwiftUI

struct ClipboardItemCustomTitleView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    let font: Font
    let textColor: Color

    var body: some View {
        if let title = item.trimmedCustomTitle {
            Text(verbatim: title)
                .font(font)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .help(title)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    viewModel.suppressNextPaste(for: item.id)
                    viewModel.renameItem(item: item)
                })
        }
    }
}
