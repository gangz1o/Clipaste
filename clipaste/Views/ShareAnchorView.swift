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
            if let originalData = await StorageManager.shared.loadOriginalImageData(id: item.id),
               let stagedURL = await ShareImageFileStager.stageImageFile(
                    data: originalData,
                    utTypeIdentifier: await StorageManager.shared.loadImageUTType(id: item.id),
                    itemID: item.id
               ) {
                objects.append(stagedURL)
            } else if let previewImage = await ClipboardImagePipeline.shared.previewImage(
                for: item.id,
                maxPixelSize: 2048
            ) {
                objects.append(previewImage)
            }
        case .fileURL:
            if let url = item.resolvedFileURL {
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

private enum ShareImageFileStager {
    private static let stagingQueue = DispatchQueue(
        label: "clipaste.share-image-stager",
        qos: .utility
    )

    static func stageImageFile(
        data: Data,
        utTypeIdentifier: String?,
        itemID: UUID
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            stagingQueue.async {
                let directoryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clipaste-share", isDirectory: true)

                do {
                    try FileManager.default.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )

                    let fileExtension = ImageProcessor.preferredFileExtension(for: utTypeIdentifier)
                    let fileURL = directoryURL.appendingPathComponent(
                        "\(itemID.uuidString).\(fileExtension)"
                    )

                    try data.write(to: fileURL, options: .atomic)
                    continuation.resume(returning: fileURL)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
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
