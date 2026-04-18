import SwiftUI

struct IgnoredAppRowView: View {
    let ignoredApp: IgnoredAppItem

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: ignoredApp.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(.rect(cornerRadius: 7))

            Text(ignoredApp.displayName)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}
