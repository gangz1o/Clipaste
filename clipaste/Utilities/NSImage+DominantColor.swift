import AppKit
import CoreImage
import Foundation

private enum AppIconColorExtractor {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    static let context = CIContext(options: [
        .cacheIntermediates: false
    ])
}

extension NSImage {
    nonisolated
    func dominantColorHex() -> String? {
        autoreleasepool {
            guard let ciImage = Self.makeCIImage(from: self) else {
                return nil
            }

            let extent = ciImage.extent.integral
            guard extent.isEmpty == false else {
                return nil
            }

            guard let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: ciImage,
                    kCIInputExtentKey: CIVector(cgRect: extent)
                ]
            ),
            let outputImage = filter.outputImage,
            let colorSpace = AppIconColorExtractor.colorSpace else {
                return nil
            }

            var pixel = [UInt8](repeating: 0, count: 4)
            AppIconColorExtractor.context.render(
                outputImage,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: colorSpace
            )

            guard pixel[3] > 0 else {
                return nil
            }

            return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
        }
    }

    private nonisolated static func makeCIImage(from image: NSImage) -> CIImage? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CIImage(cgImage: cgImage)
        }

        if let tiffRepresentation = image.tiffRepresentation {
            return CIImage(data: tiffRepresentation)
        }

        return nil
    }
}
