import SwiftUI

struct ClipboardCardView: View {
  let item: ClipboardItem
  var onSelect: () -> Void = {}
  var viewModel: ClipboardViewModel? = nil

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
        return .green
      }
    }
  }

  var body: some View {
    ZStack {
      // 水印层：复用 appIcon，位于最底层
      if let icon = item.appIcon {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          // 1. 黄金尺寸与裁剪：放大图标，使其占据绝大部分卡片，并稍微超出边界
          .frame(width: 220, height: 220)
          // 2. 灰度化：强制将图标去色，消除色彩噪音
          .saturation(0)
          // 3. 黄金透明度：设定极其克制的透明度，绝不喧宾夺主
          .opacity(0.06)
          // 4. 景深：应用轻微模糊，消除过锐的轮廓，营造“氛围”感
          .blur(radius: 5)
          // 5. 抽象对齐：将巨大的图标稍微向右下角偏移，营造高级的裁剪感
          .offset(x: 30, y: 30)
          // 6. 物理约束：确保超出卡片的部分被彻底 clipped 掉
          .clipped()
          // 7. 交互隔离：确保这个装饰层完全忽略鼠标事件
          .allowsHitTesting(false)
      }

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
    }
    .frame(width: 240, height: 240)
    // Background: 固定不随 hover 变化，避免 hover 动画
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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
    // 固定阴影，取消 hover 动画
    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    .overlay {
      if isFocused {
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color.accentColor, lineWidth: 3)
          .frame(width: 240, height: 240)
          .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 0)
          .allowsHitTesting(false)
      }
    }
    .clipboardContextMenu(for: item, viewModel: viewModel)
    .onDrag {
      NSItemProvider(object: item.id.uuidString as NSString)
    } preview: {
      ClipboardDragPreview(item: item)
    }
    // Single-click select, double-click paste
    .modifier(ClipboardCardActionModifier(item: item, onSelect: onSelect, viewModel: viewModel))
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
    Text(item.textPreview)
      .font(.system(size: 12, design: .monospaced))
      .lineLimit(6)
      .lineSpacing(2)
      .multilineTextAlignment(.leading)
      .foregroundColor(.primary.opacity(0.85))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.top, 4)
  }

  private var webPreview: some View {
    Text(item.textPreview)
      .font(.system(size: 12))
      .lineSpacing(4)
      .lineLimit(6)
      .multilineTextAlignment(.leading)
      .foregroundColor(.primary.opacity(0.85))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.top, 4)
  }

  private var imagePreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let thumbnailURL = item.thumbnailURL {
        AsyncImage(url: thumbnailURL) { phase in
          switch phase {
          case .empty:
            imagePlaceholder(showsProgress: true)
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .cornerRadius(6)
          case .failure:
            imagePlaceholder(showsProgress: false)
          @unknown default:
            imagePlaceholder(showsProgress: false)
          }
        }
      } else {
        imagePlaceholder(showsProgress: false)
      }
    }
  }

  private func imagePlaceholder(showsProgress: Bool) -> some View {
    Group {
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
      contentHash: CryptoHelper.generateHash(
        for: "Preview text of the copied content goes here. It might be long and should truncate."),
      textPreview:
        "Preview text of the copied content goes here. It might be long and should truncate.",
      appName: "Safari",
      appIconName: "safari",
      rawText: "Preview text of the copied content goes here. It might be long and should truncate."
    )
  )
  .padding()
  .background(Color.black)
}
