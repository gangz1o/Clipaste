import SwiftUI

struct IgnoredAppsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No ignored apps yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
