import SwiftUI


// MARK: - Drag Preview

struct ClipboardDragPreview: View {
    let item: ClipboardItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)

            if item.contentType == .image {
                ClipboardThumbnailView(itemID: item.id, maxPixelSize: 120) {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
                // File type: show native file icon
                let displayPath = item.fileDisplayPath ?? fileURL.path
                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else if item.isFastLink {
                // Link type: link badge
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
            } else {
                AppIconView(appBundleID: item.sourceBundleIdentifier, size: 36)
            }
        }
        .frame(width: 64, height: 64)
    }
}
