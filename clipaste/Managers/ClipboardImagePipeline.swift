import AppKit
import Foundation

@MainActor
final class ClipboardImagePipeline {
    static let shared = ClipboardImagePipeline()

    private static let thumbnailQueue = DispatchQueue(
        label: "clipaste.thumbnail-pipeline",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    func thumbnail(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        let cacheKey = "thumb-\(itemID.uuidString)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data: Data
        if let previewData = await StorageManager.shared.loadPreviewImageData(id: itemID) {
            data = previewData
        } else if let fallbackData = await StorageManager.shared.loadImageData(id: itemID) {
            data = fallbackData
        } else {
            return nil
        }

        let image = await Self.downsampleImageOffMain(data, maxPixelSize: maxPixelSize)

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    func quickLookPreviewImage(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        let cacheKey = "ql-preview-\(itemID.uuidString)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data: Data
        if let previewData = await StorageManager.shared.loadPreviewImageData(id: itemID) {
            data = previewData
        } else if let fallbackData = await StorageManager.shared.loadOriginalImageData(id: itemID) {
            data = fallbackData
        } else if let imageData = await StorageManager.shared.loadImageData(id: itemID) {
            data = imageData
        } else {
            return nil
        }

        let image = await Self.downsampleImageOffMain(data, maxPixelSize: maxPixelSize)

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    func previewImage(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        let cacheKey = "preview-\(itemID.uuidString)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data: Data
        if let originalData = await StorageManager.shared.loadOriginalImageData(id: itemID) {
            data = originalData
        } else if let previewData = await StorageManager.shared.loadPreviewImageData(id: itemID) {
            data = previewData
        } else if let fallbackData = await StorageManager.shared.loadImageData(id: itemID) {
            data = fallbackData
        } else {
            return nil
        }

        let image = await Self.downsampleImageOffMain(data, maxPixelSize: maxPixelSize)

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    func thumbnail(forFileURL fileURL: URL, maxPixelSize: Int) async -> NSImage? {
        let cacheKey = "file-thumb-\(fileURL.standardizedFileURL.path)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let image = await Self.loadAndDownsampleFileImageOffMain(
            fileURL: fileURL,
            maxPixelSize: maxPixelSize
        )

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    private static func downsampleImageOffMain(_ data: Data, maxPixelSize: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                let image = ImageProcessor.downsampleImage(from: data, maxPixelSize: maxPixelSize)
                continuation.resume(returning: image)
            }
        }
    }

    private static func loadAndDownsampleFileImageOffMain(fileURL: URL, maxPixelSize: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                guard let data = ClipboardFileReference.loadImageData(from: fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }

                let image = ImageProcessor.downsampleImage(from: data, maxPixelSize: maxPixelSize)
                continuation.resume(returning: image)
            }
        }
    }
}
