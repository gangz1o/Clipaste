import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardImageMetadata: Sendable, Hashable {
    let utTypeIdentifier: String?
    let byteCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
}

struct ImageProcessor {
    nonisolated
    static func generateThumbnail(from data: Data, maxPixelSize: Int = 800) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }

        let outputData = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                outputData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(destination, thumbnailImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return outputData as Data
    }

    nonisolated
    static func metadata(for data: Data) -> ClipboardImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ClipboardImageMetadata(
                utTypeIdentifier: nil,
                byteCount: data.count,
                pixelWidth: nil,
                pixelHeight: nil
            )
        }

        let utTypeIdentifier = CGImageSourceGetType(source) as String?
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int

        return ClipboardImageMetadata(
            utTypeIdentifier: utTypeIdentifier,
            byteCount: data.count,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    nonisolated
    static func metadata(for fileURL: URL, byteCount: Int) -> ClipboardImageMetadata {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return ClipboardImageMetadata(
                utTypeIdentifier: nil,
                byteCount: byteCount,
                pixelWidth: nil,
                pixelHeight: nil
            )
        }

        let utTypeIdentifier = CGImageSourceGetType(source) as String?
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]

        return ClipboardImageMetadata(
            utTypeIdentifier: utTypeIdentifier,
            byteCount: byteCount,
            pixelWidth: properties?[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties?[kCGImagePropertyPixelHeight] as? Int
        )
    }

    nonisolated
    static func downsampleImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return downsampleImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated
    static func downsampleImage(from fileURL: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        return downsampleImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated
    static func downsampledCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated
    private static func downsampleImage(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> NSImage? {
        guard let cgImage = makeThumbnail(from: source, maxPixelSize: maxPixelSize) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    nonisolated
    private static func makeThumbnail(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> CGImage? {
        guard maxPixelSize > 0 else { return nil }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    nonisolated
    static func preferredFileExtension(for utTypeIdentifier: String?) -> String {
        guard let utTypeIdentifier,
              let utType = UTType(utTypeIdentifier),
              let ext = utType.preferredFilenameExtension else {
            return "png"
        }

        return ext
    }

    nonisolated
    static func mimeType(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let utTypeIdentifier = CGImageSourceGetType(source) as String?,
              let utType = UTType(utTypeIdentifier),
              let mime = utType.preferredMIMEType else {
            return nil
        }
        return mime
    }
}
