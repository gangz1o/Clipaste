import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var onSelect: () -> Void = {}
    
    @State private var isHovered = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    
    private var typeIconName: String {
        if item.contentType == .image {
            return "photo"
        } else {
            switch item.appName {
            case "Xcode", "Terminal":
                return "curlybraces.square"
            case "Safari", "Google Chrome":
                return "link"
            default:
                return "doc.text"
            }
        }
    }
    
    private var typeColor: Color {
        if item.contentType == .image {
            return .purple
        } else {
            switch item.appName {
            case "Xcode", "Terminal":
                return .blue
            case "Safari", "Google Chrome":
                return .orange
            default:
                return .gray
            }
        }
    }
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                // Header: App icon, name
                HStack(spacing: 8) {
                    Group {
                        if let nsImage = item.appIcon {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    
                    // App Name
                    Text(item.appName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Image(systemName: typeIconName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Timestamp (Top Right)
                    Text(item.timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Core Content Preview
                contentPreview
                
                Spacer(minLength: 0)
            }
            .padding(12)
            
            Button("") {
                onSelect()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focused($isFocused)
        }
        .frame(width: 240, height: 240)
        // Background: glassmorphism base with adaptive opacity for hover
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.8 : 0.5))
        )
        .background(
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(typeColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // A deeper shadow on hover for interaction feedback
        .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)
        // Slight scale up effect
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .overlay {
            if isHovering || isFocused {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 0)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onAppear {
            isFocused = true
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        if item.contentType == .image {
            imagePreview
        } else {
            switch item.appName {
            case "Xcode", "Terminal":
                codePreview
            case "Safari", "Google Chrome":
                webPreview
            default:
                textPreview
            }
        }
    }
    
    private var codePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.textPreview)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(4)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var webPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.textPreview)
                .font(.system(size: 12))
                .lineSpacing(4)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var imagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnailURL = item.thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        imagePlaceholder(showsProgress: true)
                    case let .success(image):
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 120)
                                .padding(8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        imagePlaceholder(showsProgress: false)
                    @unknown default:
                        imagePlaceholder(showsProgress: false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                imagePlaceholder(showsProgress: false)
            }
        }
    }

    private func imagePlaceholder(showsProgress: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))

            if showsProgress {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var textPreview: some View {
        Text(item.textPreview)
            .font(.system(size: 12))
            .lineSpacing(4)
            .lineLimit(6)
            .multilineTextAlignment(.leading)
            .foregroundColor(.primary.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 4)
    }
}

#Preview {
    ClipboardCardView(
        item: ClipboardItem(
            contentType: .text,
            contentHash: CryptoHelper.generateHash(for: "Preview text of the copied content goes here. It might be long and should truncate."),
            textPreview: "Preview text of the copied content goes here. It might be long and should truncate.",
            appName: "Safari",
            appIconName: "safari",
            rawText: "Preview text of the copied content goes here. It might be long and should truncate."
        )
    )
    .padding()
    .background(Color.black)
}
