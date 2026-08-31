import AppKit
import Foundation

@MainActor
extension ClipboardImagePipeline {
    static func estimatedCost(for image: NSImage) -> Int {
        let width = max(1, Int(image.size.width.rounded(.up)))
        let height = max(1, Int(image.size.height.rounded(.up)))
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard pixelOverflow == false else { return Int.max }
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        return byteOverflow ? Int.max : byteCount
    }

    static func downsampleImageOffMain(
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

    static func loadAndDownsampleFileImageOffMain(
        fileURL: URL,
        maxPixelSize: Int,
        cancellation: ScreenPinLoadCancellation? = nil
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                guard cancellation?.isCancelled != true,
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

                guard let byteCount = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      byteCount > 0,
                      byteCount <= ClipboardImageResourcePolicy.maximumStoredImageByteCount else {
                    continuation.resume(returning: nil)
                    return
                }
                let metadata = ImageProcessor.metadata(for: fileURL, byteCount: byteCount)
                guard ClipboardImageResourcePolicy.allowsStoredImage(metadata) else {
                    continuation.resume(returning: nil)
                    return
                }

                let image = ImageProcessor.downsampleImage(
                    from: fileURL,
                    maxPixelSize: maxPixelSize
                )
                continuation.resume(
                    returning: cancellation?.isCancelled == true ? nil : image
                )
            }
        }
    }
}
