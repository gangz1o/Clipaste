import SwiftUI
import AppKit

/// Preview panel that shows full content of a clipboard item when hovered/focused
/// in the vertical list layout.

extension ClipboardItemPreviewView {
    @ViewBuilder
    var contentView: some View {
        switch item.contentType {
        case .text:
            textContentView
        case .image:
            imageContentView
        case .fileURL:
            fileContentView
        case .color:
            colorContentView
        case .link:
            linkContentView
        case .code:
            codeContentView
        }
    }

    // MARK: - Text Content

    @ViewBuilder
    var textContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rawText = item.rawText, !rawText.isEmpty {
                wrappedContentText(
                    rawText,
                    font: .system(size: isCompact ? 13 : 15, design: .default),
                    lineSpacing: isCompact ? 4 : 6
                )

                // Metadata
                metadataView(textLength: rawText.utf8.count)
            } else {
                emptyContentPlaceholder
            }
        }
    }

    // MARK: - Image Content

    @ViewBuilder
    var imageContentView: some View {
        VStack(spacing: 12) {
            if item.hasImagePreview || item.hasImageData {
                ZStack {
                    CheckerboardBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    ClipboardThumbnailView(itemID: item.id, maxPixelSize: isCompact ? 400 : 600) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
                .frame(height: isCompact ? 200 : 280)

                // Image dimensions if available
                if let pixelSize = item.imagePixelSize {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                emptyContentPlaceholder
            }
        }
    }

    // MARK: - File Content

    @ViewBuilder
    var fileContentView: some View {
        if let fileURL = item.resolvedFileURL {
            let displayPath = item.fileDisplayPath ?? fileURL.path

            VStack(spacing: 16) {
                if item.fileRepresentsImage {
                    // Show large thumbnail for image files
                    ZStack {
                        CheckerboardBackground()
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        ClipboardFileThumbnailView(fileURL: fileURL, maxPixelSize: isCompact ? 300 : 480) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: isCompact ? 160 : 220)
                } else {
                    // Show file icon and details
                    VStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: isCompact ? 64 : 80, height: isCompact ? 64 : 80)

                        VStack(spacing: 4) {
                            Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                .font(.system(size: isCompact ? 13 : 15, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)

                            Text(displayPath)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        } else {
            emptyContentPlaceholder
        }
    }

    // MARK: - Color Content

    @ViewBuilder
    var colorContentView: some View {
        if let parsedColor = item.fastParsedColor {
            VStack(spacing: 16) {
                // Large color swatch
                RoundedRectangle(cornerRadius: 12)
                    .fill(parsedColor)
                    .frame(height: isCompact ? 100 : 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: parsedColor.opacity(0.3), radius: 8, y: 4)

                // Color value
                if let previewText = item.previewText, !previewText.isEmpty {
                    Text(previewText)
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(parsedColor.isDark ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(parsedColor.opacity(0.2))
                        )
                }
            }
        } else {
            emptyContentPlaceholder
        }
    }

    // MARK: - Link Content

    @ViewBuilder
    var linkContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title if available
            if let title = item.linkTitle, !title.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    wrappedContentText(
                        item.textPreview,
                        font: .system(size: isCompact ? 11 : 12),
                        foregroundStyle: .secondary
                    )
                }
            } else {
                wrappedContentText(
                    item.textPreview,
                    font: .system(size: isCompact ? 13 : 14),
                    foregroundStyle: .blue
                )
            }

            Spacer(minLength: 8)

            // URL in a styled container
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                wrappedContentText(
                    item.textPreview,
                    font: .system(size: isCompact ? 10 : 11, design: .monospaced),
                    foregroundStyle: .secondary
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    // MARK: - Code Content

    @ViewBuilder
    var codeContentView: some View {
        if let rawText = item.rawText, !rawText.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                wrappedContentText(
                    rawText,
                    font: .system(size: isCompact ? 12 : 13, design: .monospaced),
                    lineSpacing: isCompact ? 3 : 4
                )

                metadataView(textLength: rawText.utf8.count)
            }
        } else {
            emptyContentPlaceholder
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    func metadataView(textLength: Int) -> some View {
        HStack(spacing: 16) {
            if textLength > 0 {
                Label("\(textLength) chars", systemImage: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if item.sourceBundleIdentifier != nil {
                Label(item.appName, systemImage: "app.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    func wrappedContentText(
        _ text: String,
        font: Font,
        lineSpacing: CGFloat = 0,
        foregroundStyle: some ShapeStyle = .primary
    ) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }

    @ViewBuilder
    var emptyContentPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No preview available")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: isCompact ? 120 : 180)
    }
}
