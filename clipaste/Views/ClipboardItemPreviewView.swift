import SwiftUI
import AppKit

/// Preview panel that shows full content of a clipboard item when hovered/focused
/// in the vertical list layout.
struct ClipboardItemPreviewView: View {
    let item: ClipboardItem

    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal

    private var isCompact: Bool {
        clipboardLayout == .compact
    }

    private var panelMinWidth: CGFloat {
        isCompact ? 300 : 420
    }

    private var panelIdealWidth: CGFloat {
        isCompact ? 360 : 520
    }

    private var panelMaxWidth: CGFloat {
        isCompact ? 420 : 680
    }

    private var panelCornerRadius: CGFloat {
        isCompact ? 10 : 14
    }

    private var padding: CGFloat {
        isCompact ? 12 : 16
    }

    private var headerHeight: CGFloat {
        isCompact ? 44 : 56
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with type badge and timestamp
            headerView
                .frame(height: headerHeight)
            
            Divider()
                .opacity(0.1)
            
            // Content area
            ScrollView {
                contentView
                    .padding(padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: panelMinWidth,
            idealWidth: panelIdealWidth,
            maxWidth: panelMaxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .layoutPriority(1)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 12) {
            // Type badge
            HStack(spacing: 4) {
                Image(systemName: item.contentType.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(item.typeBadgeTitle())
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(typeBadgeColor)
            .clipShape(Capsule())
            
            Spacer()
            
            // Timestamp
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.timestamp.timeString)
                    .font(.system(size: 12, weight: .medium))
                Text(item.timestamp.dateString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var typeBadgeColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .image: return .purple
        case .fileURL: return .orange
        case .color: return .pink
        case .link: return .green
        case .code: return .gray
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
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
    private var textContentView: some View {
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
    private var imageContentView: some View {
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
    private var fileContentView: some View {
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
    private var colorContentView: some View {
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
    private var linkContentView: some View {
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
    private var codeContentView: some View {
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
    private func metadataView(textLength: Int) -> some View {
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

    private func wrappedContentText(
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
    private var emptyContentPlaceholder: some View {
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

// MARK: - Checkerboard Background

/// Classic gray-white checkerboard pattern for transparent image visualization
private struct CheckerboardBackground: View {
    let cellSize: CGFloat = 10
    let lightColor = Color.white.opacity(0.9)
    let darkColor = Color.gray.opacity(0.2)
    
    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(Path(rect), with: .color(isEven ? lightColor : darkColor))
                }
            }
        }
        .accessibilityLabel("Checkerboard pattern for transparent image background")
    }
}

#Preview {
    HStack(spacing: 20) {
        ClipboardItemPreviewView(
            item: ClipboardItem(
                contentType: .text,
                contentHash: "preview1",
                textPreview: "Sample text content for preview",
                appName: "Safari",
                appIconName: "safari",
                rawText: "This is a longer piece of text that would normally be truncated in the list view. Now we can see the full content in the preview panel.\n\nIt can span multiple lines and include paragraphs."
            )
        )

        ClipboardItemPreviewView(
            item: ClipboardItem(
                contentType: .code,
                contentHash: "preview2",
                textPreview: "let greeting = \"Hello, World!\"",
                appName: "Xcode",
                appIconName: "xcode",
                rawText: "func greet(name: String) -> String {\n    return \"Hello, \\(name)!\"\n}\n\ngreet(name: \"World\")"
            )
        )
    }
    .padding()
    .background(Color.black)
}
