import SwiftUI
import AppKit

// MARK: - ShareableModifier

/// 给卡片附加"右键分享"能力的 ViewModifier。
/// 原理：用 .background(NSViewRepresentable) 捕获和卡片同尺寸的 NSView，
/// 再用 .onChange(of: sharingItem) 触发 NSSharingServicePicker，
/// 确保分享面板精确弹出在卡片上方。
struct ShareableModifier: ViewModifier {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel

    /// 存储捕获到的 NSView 引用
    private class AnchorStore {
        weak var view: NSView?
        static let shared = NSMapTable<NSString, NSView>.strongToWeakObjects()
    }

    func body(content: Content) -> some View {
        content
            // 透明背景层：和卡片同尺寸，用于提供 NSView 锚点
            .background(
                AnchorCapture(itemId: item.id.uuidString)
                    .allowsHitTesting(false)
            )
            // 监听 sharingItem 变化
            .onChange(of: viewModel.sharingItem?.id) { _, newId in
                guard newId == item.id else { return }
                showSharePicker()
            }
    }

    private func showSharePicker() {
        Task {
            let objects = await buildShareObjects()
            guard !objects.isEmpty else {
                await MainActor.run {
                    viewModel.sharingItem = nil
                }
                return
            }

            await MainActor.run {
                let anchorView = AnchorCapture.viewStore.object(forKey: item.id.uuidString as NSString)
                    ?? (NSApp.keyWindow ?? NSApp.windows.first(where: { $0 is ClipboardPanel }))?.contentView

                guard let anchor = anchorView else {
                    viewModel.sharingItem = nil
                    return
                }

                let picker = NSSharingServicePicker(items: objects)
                picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                viewModel.sharingItem = nil
            }
        }
    }

    private func buildShareObjects() async -> [Any] {
        var objects: [Any] = []

        switch item.contentType {
        case .image:
            let imageData = await StorageManager.shared.loadImageData(id: item.id)
            let previewData = await StorageManager.shared.loadPreviewImageData(id: item.id)
            if let data = imageData ?? previewData,
               let image = NSImage(data: data) {
                objects.append(image)
            }
        case .fileURL:
            if let urlStr = item.fileURL, let url = URL(string: urlStr), url.isFileURL {
                objects.append(url)
            } else if let text = item.rawText ?? item.previewText {
                objects.append(text)
            }
        default:
            if let text = item.rawText ?? item.previewText {
                objects.append(text)
            }
        }

        return objects
    }
}

// MARK: - AnchorCapture

/// 极简 NSViewRepresentable：唯一职责是把 NSView 引用存入全局弱引用表，
/// 供 ShareableModifier 在 onChange 时取回。
private struct AnchorCapture: NSViewRepresentable {
    let itemId: String

    /// 全局弱引用表：key = item UUID string, value = NSView (weak)
    static let viewStore = NSMapTable<NSString, NSView>.strongToWeakObjects()

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        Self.viewStore.setObject(v, forKey: itemId as NSString)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.viewStore.setObject(nsView, forKey: itemId as NSString)
    }
}

// MARK: - View Extensions

extension View {
    func shareable(item: ClipboardItem, viewModel: ClipboardViewModel) -> some View {
        modifier(ShareableModifier(item: item, viewModel: viewModel))
    }
}

/// 处理 viewModel 为 optional 的场景（ClipboardCardView 中 viewModel 是 optional）
struct OptionalShareModifier: ViewModifier {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel?

    func body(content: Content) -> some View {
        if let viewModel {
            content.shareable(item: item, viewModel: viewModel)
        } else {
            content
        }
    }
}
