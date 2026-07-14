import AppKit
import SwiftUI

struct ScreenPinnedImageView: View {
    let image: NSImage
    let closeAction: () -> Void

    @State private var isCloseButtonHovered = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.08))
            .overlay {
                ScreenPinWindowDragView()
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                closeButton
                    .padding(8)
            }
            .clipShape(.rect(cornerRadius: 6))
    }

    private var closeButton: some View {
        Button("Close Pinned Image", systemImage: "xmark", action: closeAction)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: .circle)
            .overlay {
                Circle()
                    .stroke(.white.opacity(isCloseButtonHovered ? 0.35 : 0.18), lineWidth: 0.5)
            }
            .opacity(isCloseButtonHovered ? 1 : 0.72)
            .onHover { isCloseButtonHovered = $0 }
            .help(Text("Close Pinned Image"))
    }
}
