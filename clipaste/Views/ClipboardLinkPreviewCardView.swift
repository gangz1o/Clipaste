import AppKit
import SwiftUI

struct ClipboardLinkPreviewCardView: View {
    let viewModel: ClipboardLinkPreviewViewModel
    let highlight: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinkPreviewTitleLine(
                viewModel: viewModel,
                highlight: highlight,
                iconSize: 18,
                titleFontSize: 14,
                titleWeight: .semibold
            )

            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text(viewModel.domain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(viewModel.displayURL)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .help(viewModel.fullURL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.displayURL)"))
    }
}

struct ClipboardLinkPreviewRowView: View {
    let viewModel: ClipboardLinkPreviewViewModel
    let highlight: String
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 0 : 3) {
            LinkPreviewTitleLine(
                viewModel: viewModel,
                highlight: highlight,
                iconSize: isCompact ? 14 : 16,
                titleFontSize: isCompact ? 11 : 13,
                titleWeight: .medium
            )

            if !isCompact {
                Text(viewModel.displayURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.displayURL)"))
    }
}

struct ClipboardLinkPlainCardView: View {
    let viewModel: ClipboardLinkPreviewViewModel
    let highlight: String

    var body: some View {
        HighlightedText(
            text: viewModel.fullURL,
            highlight: highlight,
            font: .system(size: 12, design: .monospaced),
            foregroundColor: .secondary,
            highlightFont: .system(size: 12, weight: .bold, design: .monospaced)
        )
        .lineSpacing(3)
        .lineLimit(8)
        .truncationMode(.middle)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help(viewModel.fullURL)
        .accessibilityLabel(Text(verbatim: viewModel.fullURL))
    }
}

struct ClipboardLinkPlainRowView: View {
    let viewModel: ClipboardLinkPreviewViewModel
    let highlight: String
    let isCompact: Bool

    var body: some View {
        HighlightedText(
            text: viewModel.fullURL,
            highlight: highlight,
            font: .system(size: isCompact ? 11 : 13),
            foregroundColor: .secondary,
            highlightFont: .system(size: isCompact ? 11 : 13, weight: .semibold)
        )
        .lineLimit(isCompact ? 1 : 2)
        .truncationMode(.middle)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(viewModel.fullURL)
        .accessibilityLabel(Text(verbatim: viewModel.fullURL))
    }
}

private struct LinkPreviewTitleLine: View {
    let viewModel: ClipboardLinkPreviewViewModel
    let highlight: String
    let iconSize: CGFloat
    let titleFontSize: CGFloat
    let titleWeight: Font.Weight

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            LinkPreviewIcon(data: viewModel.iconData, size: iconSize)

            HighlightedText(
                text: viewModel.title,
                highlight: highlight,
                font: .system(size: titleFontSize, weight: titleWeight),
                foregroundColor: .primary,
                highlightFont: .system(
                    size: titleFontSize,
                    weight: titleWeight == .semibold ? .bold : .semibold
                )
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinkPreviewIcon: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "link")
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous)
                .fill(image == nil ? Color.primary.opacity(0.055) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous)
                .stroke(image == nil ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }

    private var image: NSImage? {
        guard let data else { return nil }
        return NSImage(data: data)
    }
}
