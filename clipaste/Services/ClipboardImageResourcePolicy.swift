import Foundation

enum ClipboardImageResourcePolicy {
    nonisolated static let maximumStoredImageByteCount = 64 * 1024 * 1024
    nonisolated static let maximumStoredImagePixelCount = 100_000_000
    nonisolated static let maximumOCRPixelSize = 2_048
    nonisolated static let maximumScreenPinPixelSize = 4_096

    nonisolated static func allowsStoredImage(_ metadata: ClipboardImageMetadata) -> Bool {
        guard metadata.byteCount > 0,
              metadata.byteCount <= maximumStoredImageByteCount,
              let width = metadata.pixelWidth,
              let height = metadata.pixelHeight,
              width > 0,
              height > 0 else {
            return false
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow == false && pixelCount <= maximumStoredImagePixelCount
    }

    nonisolated static func boundedScreenPinPixelSize(_ requestedSize: Int) -> Int {
        max(256, min(requestedSize, maximumScreenPinPixelSize))
    }
}
