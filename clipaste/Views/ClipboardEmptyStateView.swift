import SwiftUI

struct ClipboardEmptyStateView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isSearching ? "doc.text.magnifyingglass" : "tray.fill")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(isSearching ? "No Matches Found" : "Clipboard Empty")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(isSearching ? "Try a different search term" : "Copied text, images and links will appear here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
    }

    private var isSearching: Bool {
        !viewModel.searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
