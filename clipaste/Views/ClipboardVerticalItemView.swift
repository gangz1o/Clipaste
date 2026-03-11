import SwiftUI

struct ClipboardVerticalItemView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            // 1. 左侧：App 图标
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
            } else {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Image(systemName: "app.dashed").foregroundColor(.secondary)
                }
                .frame(width: 36, height: 36)
            }

            // 2. 中间：内容预览
            VStack(alignment: .leading, spacing: 4) {
                if item.contentType == .image, let url = item.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 40)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 40)
                        }
                    }
                } else {
                    Text(item.textPreview.isEmpty ? "（空）" : item.textPreview)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. 右侧：时间
            VStack(alignment: .trailing, spacing: 10) {
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer().frame(height: 12)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1.0 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .clipboardContextMenu(for: item, viewModel: viewModel)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            ClipboardDragPreview(item: item)
        }
        .clipboardItemActions(for: item, viewModel: viewModel)
    }
}

// MARK: - Drag Preview

struct ClipboardDragPreview: View {
    let item: ClipboardItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)

            if item.contentType == .image, let url = item.thumbnailURL,
               let img = NSImage(contentsOf: url) {
                // Image type: show actual thumbnail
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if item.rawText?.lowercased().hasPrefix("http") == true {
                // Link type: link badge
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
            } else if let icon = item.appIcon {
                // Has source app: show its icon
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else {
                // Plain text / fallback
                Image(systemName: "doc.text.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 36)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 64, height: 64)
    }
}
