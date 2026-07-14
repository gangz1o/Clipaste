import SwiftUI

struct ScreenPinIconDragTarget: View {
    let isActive: Bool
    let onDragEnded: (CGPoint) -> Void

    var body: some View {
        if isActive {
            ScreenPinDragSourceView(onDragEnded: onDragEnded)
                .help(Text("Drag to Pin on Screen"))
        }
    }
}
