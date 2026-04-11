import SwiftUI

struct ClipboardOperationNoticeView: View {
    let message: String

    var body: some View {
        Text(verbatim: message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 3)
            .accessibilityLabel(Text(verbatim: message))
    }
}
