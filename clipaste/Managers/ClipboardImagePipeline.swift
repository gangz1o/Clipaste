import AppKit
import Foundation

private final class ScreenPinLoadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
final class ClipboardImagePipeline {
    static let shared = ClipboardImagePipeline()

    private static let thumbnailQueue = DispatchQueue(
        label: "clipaste.thumbnail-pipeline",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private struct ScreenPinLoadEntry {
        let id: UUID
        let task: Task<NSImage?, Never>
        let cancellation: ScreenPinLoadCancellation
    }

    private let cache = NSCache<NSString, NSImage>()
    private var screenPinLoadTasks: [String: ScreenPinLoadEntry] = [:]

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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(for: image))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(for: image))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(for: image))
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
            cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(for: image))
        }

        return image
    }

    func screenPinImage(for item: ClipboardItem, maxPixelSize: Int) async -> NSImage? {
        guard item.isScreenPinEligible else { return nil }

        if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
            return await screenPinImage(forFileURL: fileURL, maxPixelSize: maxPixelSize)
        }

        let boundedPixelSize = Self.boundedScreenPinPixelSize(maxPixelSize)
        let taskKey = "screen-pin-\(item.id.uuidString)-\(boundedPixelSize)"
        let cacheKey = taskKey as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        if let existingEntry = screenPinLoadTasks[taskKey] {
            return await existingEntry.task.value
        }

        let loadID = UUID()
        let cancellation = ScreenPinLoadCancellation()
        let loadTask = Task<NSImage?, Never> { [item] in
            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }

            let data: Data
            if let originalData = await StorageManager.shared.loadOriginalImageData(id: item.id) {
                data = originalData
            } else if let imageData = await StorageManager.shared.loadImageData(id: item.id) {
                data = imageData
            } else if let previewData = await StorageManager.shared.loadPreviewImageData(id: item.id) {
                data = previewData
            } else {
                return nil
            }

            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }
            let image = await Self.downsampleImageOffMain(
                data,
                maxPixelSize: boundedPixelSize,
                cancellation: cancellation
            )
            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }

            if let image {
                cache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: Self.estimatedCost(for: image)
                )
            }

            return image
        }

        screenPinLoadTasks[taskKey] = ScreenPinLoadEntry(
            id: loadID,
            task: loadTask,
            cancellation: cancellation
        )
        let image = await loadTask.value
        if screenPinLoadTasks[taskKey]?.id == loadID {
            screenPinLoadTasks.removeValue(forKey: taskKey)
        }
        return image
    }

    private func screenPinImage(forFileURL fileURL: URL, maxPixelSize: Int) async -> NSImage? {
        let boundedPixelSize = Self.boundedScreenPinPixelSize(maxPixelSize)
        let taskKey = "screen-pin-file-\(fileURL.standardizedFileURL.path)-\(boundedPixelSize)"
        let cacheKey = taskKey as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        if let existingEntry = screenPinLoadTasks[taskKey] {
            return await existingEntry.task.value
        }

        let loadID = UUID()
        let cancellation = ScreenPinLoadCancellation()
        let loadTask = Task<NSImage?, Never> {
            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }
            guard let data = await Self.loadScreenPinFileDataOffMain(
                fileURL: fileURL,
                cancellation: cancellation
            ) else {
                return nil
            }
            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }
            let image = await Self.downsampleImageOffMain(
                data,
                maxPixelSize: boundedPixelSize,
                cancellation: cancellation
            )
            guard Task.isCancelled == false, cancellation.isCancelled == false else { return nil }

            if let image {
                cache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: Self.estimatedCost(for: image)
                )
            }

            return image
        }

        screenPinLoadTasks[taskKey] = ScreenPinLoadEntry(
            id: loadID,
            task: loadTask,
            cancellation: cancellation
        )
        let image = await loadTask.value
        if screenPinLoadTasks[taskKey]?.id == loadID {
            screenPinLoadTasks.removeValue(forKey: taskKey)
        }
        return image
    }

    func cancelScreenPinLoads() {
        for entry in screenPinLoadTasks.values {
            entry.cancellation.cancel()
            entry.task.cancel()
        }
        screenPinLoadTasks.removeAll(keepingCapacity: false)
    }

    /// NSCache cost must track decoded memory, not compressed source bytes.
    private static func estimatedCost(for image: NSImage) -> Int {
        let width = max(1, Int(image.size.width.rounded(.up)))
        let height = max(1, Int(image.size.height.rounded(.up)))
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard pixelOverflow == false else { return Int.max }
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        return byteOverflow ? Int.max : byteCount
    }

    private static func boundedScreenPinPixelSize(_ requestedSize: Int) -> Int {
        max(256, min(requestedSize, 4096))
    }

    private static func downsampleImageOffMain(
        _ data: Data,
        maxPixelSize: Int,
        cancellation: ScreenPinLoadCancellation? = nil
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                guard cancellation?.isCancelled != true else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = ImageProcessor.downsampleImage(from: data, maxPixelSize: maxPixelSize)
                continuation.resume(returning: cancellation?.isCancelled == true ? nil : image)
            }
        }
    }

    private static func loadScreenPinFileDataOffMain(
        fileURL: URL,
        cancellation: ScreenPinLoadCancellation
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                guard cancellation.isCancelled == false,
                      ClipboardFileReference.isLikelyImageFileURL(fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }

                let didStartSecurityScope = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartSecurityScope {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { try? handle.close() }

                var data = Data()
                do {
                    while cancellation.isCancelled == false {
                        guard let chunk = try handle.read(upToCount: 1024 * 1024),
                              chunk.isEmpty == false else {
                            break
                        }
                        data.append(chunk)
                    }
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: cancellation.isCancelled ? nil : data)
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
