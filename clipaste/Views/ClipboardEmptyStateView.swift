import SwiftUI

struct ClipboardEmptyStateView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal

    var body: some View {
        Group {
            if isLoading {
                loadingPlaceholder
            } else {
                emptyStateContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isSearching: Bool {
        !viewModel.searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLoading: Bool {
        viewModel.isInitialHistoryLoading && !isSearching
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        if clipboardLayout == .horizontal {
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 240, height: 240)
                        .overlay(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 52)
                        }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 12)
        } else {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 76)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 12)
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            Image(systemName: isSearching ? "doc.text.magnifyingglass" : "tray.fill")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 40)
    }

    private var titleKey: LocalizedStringKey {
        if isLoading {
            return "Loading Clipboard History…"
        }

        return isSearching ? "No Matches Found" : "Clipboard Empty"
    }

    private var subtitleKey: LocalizedStringKey {
        if isLoading {
            return "Recent items will appear first while the full history finishes loading."
        }

        return isSearching ? "Try a different search term" : "Copied text, images and links will appear here"
    }
}
