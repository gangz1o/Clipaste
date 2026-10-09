import AppKit
import Foundation

private nonisolated enum AppIconColorExtraction {
    static let workingSize = 48
    /// 低于该不透明度的像素视为阴影 / 抗锯齿边缘，不参与取色。
    static let minimumAlpha: Double = 0.6
    static let minimumSaturation: Double = 0.28
    static let minimumBrightness: Double = 0.30
    static let minimumChroma: Double = 0.18
    /// 有色像素占比低于该值时，图标视为中性色（黑 / 白 / 灰）。
    static let minimumChromaticCoverage: Double = 0.06
    static let hueBinCount = 36
    /// 峰值两侧纳入平均的色相范围（以 bin 为单位）。
    static let hueWindowBins: Double = 1.5
    /// 中性色图标的亮度上限，保证卡片头部的白色文字可读。
    static let neutralMaximumBrightness: Double = 0.42
}

extension NSImage {
    /// 取图标的「品牌色」：在有色像素上做环形色相直方图，取峰值附近像素的加权平均；
    /// 图标几乎没有颜色时，退回到压暗后的中性色平均值。
    nonisolated
    func dominantColorHex() -> String? {
        autoreleasepool {
            guard let bitmap = Self.makeBitmap(from: self, size: AppIconColorExtraction.workingSize),
                  let bitmapData = bitmap.bitmapData else {
                return nil
            }

            let binCount = AppIconColorExtraction.hueBinCount
            var histogram = [Double](repeating: 0, count: binCount)
            var chromaticPixels: [ChromaticPixel] = []
            var neutral = ColorAccumulator()
            var opaqueCount = 0

            let pixelCount = bitmap.pixelsWide * bitmap.pixelsHigh
            for pixelIndex in 0..<pixelCount {
                let offset = pixelIndex * 4
                let alpha = Double(bitmapData[offset + 3]) / 255.0
                guard alpha >= AppIconColorExtraction.minimumAlpha else {
                    continue
                }

                // 位图是预乘 alpha 的，先还原真实颜色。
                let color = RGBColor(
                    red: min(Double(bitmapData[offset]) / 255.0 / alpha, 1),
                    green: min(Double(bitmapData[offset + 1]) / 255.0 / alpha, 1),
                    blue: min(Double(bitmapData[offset + 2]) / 255.0 / alpha, 1)
                )
                let hsv = color.hsv
                let chroma = hsv.saturation * hsv.value
                opaqueCount += 1

                guard hsv.saturation >= AppIconColorExtraction.minimumSaturation,
                      hsv.value >= AppIconColorExtraction.minimumBrightness,
                      chroma >= AppIconColorExtraction.minimumChroma else {
                    neutral.add(color, weight: 1)
                    continue
                }

                histogram[Int(hsv.hue * Double(binCount)) % binCount] += chroma
                chromaticPixels.append(ChromaticPixel(color: color, hue: hsv.hue, weight: chroma))
            }

            guard opaqueCount > 0 else {
                return nil
            }

            let coverage = Double(chromaticPixels.count) / Double(opaqueCount)
            if coverage >= AppIconColorExtraction.minimumChromaticCoverage,
               let brandColor = Self.peakHueColor(histogram: histogram, pixels: chromaticPixels) {
                return brandColor.hex
            }

            return neutral.average?.clampingBrightness(to: AppIconColorExtraction.neutralMaximumBrightness).hex
        }
    }

    private nonisolated static func peakHueColor(histogram: [Double], pixels: [ChromaticPixel]) -> RGBColor? {
        let binCount = histogram.count
        // 环形平滑：避免跨在 bin 边界（例如 0° / 360° 的红色）的同一种颜色被拆散。
        let smoothed = histogram.indices.map { index in
            histogram[(index + binCount - 1) % binCount] * 0.5
                + histogram[index]
                + histogram[(index + 1) % binCount] * 0.5
        }

        guard let peakIndex = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }),
              smoothed[peakIndex] > 0 else {
            return nil
        }

        let peakHue = (Double(peakIndex) + 0.5) / Double(binCount)
        let window = AppIconColorExtraction.hueWindowBins / Double(binCount)
        var accumulator = ColorAccumulator()

        for pixel in pixels {
            let distance = abs(pixel.hue - peakHue)
            guard min(distance, 1 - distance) <= window else {
                continue
            }
            accumulator.add(pixel.color, weight: pixel.weight)
        }

        return accumulator.average
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
}

private nonisolated struct ChromaticPixel {
    let color: RGBColor
    let hue: Double
    let weight: Double
}

private nonisolated struct ColorAccumulator {
    private var totalWeight: Double = 0
    private var weightedRed: Double = 0
    private var weightedGreen: Double = 0
    private var weightedBlue: Double = 0

    mutating func add(_ color: RGBColor, weight: Double) {
        totalWeight += weight
        weightedRed += color.red * weight
        weightedGreen += color.green * weight
        weightedBlue += color.blue * weight
    }

    var average: RGBColor? {
        guard totalWeight > 0 else { return nil }
        return RGBColor(
            red: weightedRed / totalWeight,
            green: weightedGreen / totalWeight,
            blue: weightedBlue / totalWeight
        )
    }
}

private nonisolated struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    var hex: String {
        func component(_ value: Double) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255.0).rounded())
        }
        return String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }

    func clampingBrightness(to maximum: Double) -> RGBColor {
        let brightness = max(red, green, blue)
        guard brightness > maximum else { return self }
        let scale = maximum / brightness
        return RGBColor(red: red * scale, green: green * scale, blue: blue * scale)
    }

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
