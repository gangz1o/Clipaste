import AppKit

@MainActor
final class ClipboardQuickLookImageService {
    static let shared = ClipboardQuickLookImageService()

    private init() {}

    func loadInitialImage(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        await ClipboardImagePipeline.shared.quickLookPreviewImage(
            for: itemID,
            maxPixelSize: maxPixelSize
        )
    }

    func loadUpgradedImage(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        await ClipboardImagePipeline.shared.previewImage(
            for: itemID,
            maxPixelSize: maxPixelSize
        )
    }

    func prewarmInitialImage(for itemID: UUID, maxPixelSize: Int) {
        Task {
            _ = await ClipboardImagePipeline.shared.quickLookPreviewImage(
                for: itemID,
                maxPixelSize: maxPixelSize
            )
        }
    }

    func shouldUpgradeInitialImage(
        _ image: NSImage,
        targetDisplaySize: CGSize
    ) -> Bool {
        ClipboardImagePreviewPolicy.shouldUpgradeQuickLookImage(
            currentImageSize: image.size,
            targetDisplaySize: targetDisplaySize,
            scaleFactor: currentScreenScaleFactor
        )
    }

    private var currentScreenScaleFactor: CGFloat {
        NSScreen.main?.backingScaleFactor
            ?? NSScreen.screens.first?.backingScaleFactor
            ?? 2
    }
}
