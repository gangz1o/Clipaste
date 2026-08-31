import SwiftUI
import AppKit

/// Preview panel that shows full content of a clipboard item when hovered/focused
/// in the vertical list layout.
struct ClipboardItemPreviewView: View {
    let item: ClipboardItem

    @AppStorage("clipboardLayout") var clipboardLayout: AppLayoutMode = .horizontal

    var isCompact: Bool {
        clipboardLayout == .compact
    }

    var panelMinWidth: CGFloat {
        isCompact ? 300 : 420
    }

    var panelIdealWidth: CGFloat {
        isCompact ? 360 : 520
    }

    var panelMaxWidth: CGFloat {
        isCompact ? 420 : 680
    }

    var panelCornerRadius: CGFloat {
        isCompact ? 10 : 14
    }

    var padding: CGFloat {
        isCompact ? 12 : 16
    }

    var headerHeight: CGFloat {
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
    var headerView: some View {
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
    
    var typeBadgeColor: Color {
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
    
}
