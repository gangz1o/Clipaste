import AppKit
import CoreImage
import Foundation

private nonisolated enum AppIconColorExtraction {
    static let workingSize = 32
    static let minimumAlpha: Double = 0.18
    static let minimumSaturation: Double = 0.20
    static let neutralBrightnessCutoff: Double = 0.78
    static let sharedContext = CIContext(options: [.cacheIntermediates: false])
}

extension NSImage {
    nonisolated
    func dominantColorHex() -> String? {
        autoreleasepool {
            if let histogramColor = Self.histogramDominantColorHex(from: self) {
                return histogramColor
            }

            return Self.areaAverageHex(from: self)
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

    private nonisolated static func histogramDominantColorHex(from image: NSImage) -> String? {
        guard let bitmap = makeBitmap(from: image, size: AppIconColorExtraction.workingSize),
              let bitmapData = bitmap.bitmapData else {
            return nil
        }

        let bytesPerPixel = 4
        let pixelCount = bitmap.pixelsWide * bitmap.pixelsHigh
        var bins: [Int: ColorBin] = [:]
        var fallback = ColorBin()

        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * bytesPerPixel
            let red = Double(bitmapData[offset]) / 255.0
            let green = Double(bitmapData[offset + 1]) / 255.0
            let blue = Double(bitmapData[offset + 2]) / 255.0
            let alpha = Double(bitmapData[offset + 3]) / 255.0

            guard alpha >= AppIconColorExtraction.minimumAlpha else {
                continue
            }

            let hsv = RGBColor(red: red, green: green, blue: blue).hsv
            fallback.add(red: red, green: green, blue: blue, alpha: alpha, weight: alpha)

            let isNearWhiteOrGray =
                hsv.saturation < AppIconColorExtraction.minimumSaturation &&
                hsv.value > AppIconColorExtraction.neutralBrightnessCutoff
            guard !isNearWhiteOrGray else {
                continue
            }

            let shouldTreatAsAccent =
                hsv.saturation >= AppIconColorExtraction.minimumSaturation || hsv.value < 0.42
            guard shouldTreatAsAccent else {
                continue
            }

            let bucket = colorBucket(for: hsv, red: red, green: green, blue: blue)
            let weight = alpha * max(hsv.saturation, 0.35) * (0.55 + hsv.value * 0.45)
            bins[bucket, default: ColorBin()].add(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha,
                weight: weight
            )
        }

        if let best = bins.max(by: { $0.value.totalWeight < $1.value.totalWeight })?.value,
           let color = best.hex {
            return color
        }

        return fallback.hex
    }

    private nonisolated static func makeBitmap(from image: NSImage, size: Int) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        )

        guard let rep else { return nil }

        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        context.imageInterpolation = .high

        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        return rep
    }

    private nonisolated static func colorBucket(for hsv: HSVColor, red: Double, green: Double, blue: Double) -> Int {
        let hueBucket = Int((hsv.hue * 24.0).rounded(.down)) % 24
        let saturationBucket = min(Int(hsv.saturation * 4.0), 3)
        let brightnessBucket = min(Int(hsv.value * 4.0), 3)
        let dominantChannel = dominantChannelIndex(red: red, green: green, blue: blue)
        return (((hueBucket * 4) + saturationBucket) * 4 + brightnessBucket) * 4 + dominantChannel
    }

    private nonisolated static func dominantChannelIndex(red: Double, green: Double, blue: Double) -> Int {
        if red >= green && red >= blue { return 0 }
        if green >= red && green >= blue { return 1 }
        return 2
    }

    private nonisolated static func areaAverageHex(from image: NSImage) -> String? {
        guard let ciImage = makeCIImage(from: image) else {
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
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        AppIconColorExtraction.sharedContext.render(
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

private nonisolated struct ColorBin {
    private(set) var totalWeight: Double = 0
    private var weightedRed: Double = 0
    private var weightedGreen: Double = 0
    private var weightedBlue: Double = 0

    mutating func add(red: Double, green: Double, blue: Double, alpha _: Double, weight: Double) {
        totalWeight += weight
        weightedRed += red * weight
        weightedGreen += green * weight
        weightedBlue += blue * weight
    }

    var hex: String? {
        guard totalWeight > 0 else { return nil }
        let red = UInt8((weightedRed / totalWeight * 255.0).rounded())
        let green = UInt8((weightedGreen / totalWeight * 255.0).rounded())
        let blue = UInt8((weightedBlue / totalWeight * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private nonisolated struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    var hsv: HSVColor {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hue = ((blue - red) / delta) + 2
        } else {
            hue = ((red - green) / delta) + 4
        }

        let normalizedHue = ((hue / 6).truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1)
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return HSVColor(hue: normalizedHue, saturation: saturation, value: maxValue)
    }
}

private nonisolated struct HSVColor {
    let hue: Double
    let saturation: Double
    let value: Double
}
