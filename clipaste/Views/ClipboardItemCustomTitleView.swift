import AppKit
import SwiftUI

struct ClipboardItemCustomTitleView: View {
    let item: ClipboardItem
    var viewModel: ClipboardViewModel
    let font: Font
    let textColor: Color
    @State private var isHovering = false

    var body: some View {
        if let title = item.trimmedCustomTitle {
            Text(verbatim: title)
                .font(font)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .help(title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.clear)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture(count: 2).onEnded {
                    viewModel.suppressNextPaste(for: item.id)
                    viewModel.renameItem(item: item)
                })
                .onHover(perform: updateCursor)
        }
    }

    private func updateCursor(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering

        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}
