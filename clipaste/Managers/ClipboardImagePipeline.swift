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
        // 64 MB upper bound — Quick Look 高分图 + 列表缩略图共享同一个 cache，
        // 没有 byte-level 上限时菜单栏应用持续运行会一路涨到几百 MB。
        cache.totalCostLimit = 64 * 1024 * 1024
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(forPixelSize: maxPixelSize, sourceByteCount: data.count))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(forPixelSize: maxPixelSize, sourceByteCount: data.count))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(forPixelSize: maxPixelSize, sourceByteCount: data.count))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(forPixelSize: maxPixelSize, sourceByteCount: 0))
        }

        return image
    }

    /// 估算单张缓存项的字节数。downsample 后图像约为 maxPixelSize² × 4 字节（RGBA）；
    /// 当源数据更小时退化到源数据大小，避免高估。
    private static func estimatedCost(forPixelSize maxPixelSize: Int, sourceByteCount: Int) -> Int {
        let bounded = max(64, min(maxPixelSize, 4096))
        let pixelEstimate = bounded * bounded * 4
        guard sourceByteCount > 0 else { return pixelEstimate }
        return min(pixelEstimate, sourceByteCount * 4)
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
