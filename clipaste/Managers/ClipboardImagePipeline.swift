import AppKit
import Foundation

final class ClipboardImagePipeline: @unchecked Sendable {
    nonisolated static let shared = ClipboardImagePipeline()

    nonisolated(unsafe) private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    nonisolated func invalidateAll() {
        cache.removeAllObjects()
    }

    nonisolated func thumbnail(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
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

        let image = await Task.detached(priority: .userInitiated) {
            ImageProcessor.downsampleImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    nonisolated func fullImage(for itemID: UUID, maxPixelSize: Int) async -> NSImage? {
        let cacheKey = "full-\(itemID.uuidString)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data: Data
        if let fullData = await StorageManager.shared.loadImageData(id: itemID) {
            data = fullData
        } else if let fallbackData = await StorageManager.shared.loadPreviewImageData(id: itemID) {
            data = fallbackData
        } else {
            return nil
        }

        let image = await Task.detached(priority: .userInitiated) {
            ImageProcessor.downsampleImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }
}
