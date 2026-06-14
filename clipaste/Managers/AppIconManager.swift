import AppKit

final class AppIconManager {
    static let shared = AppIconManager()

    static let syncedIconPixelSize: CGFloat = 128

    private let cache = NSCache<NSString, NSImage>()
    /// 已编码的 PNG 数据按 bundleID + pixelSize 缓存。每次剪贴板写入都触发
    /// `pngData` 路径（drawing + tiffRepresentation + PNG encode），同一个 App
    /// 反复编码同一张图非常吃主线程。
    private let pngDataCache = NSCache<NSString, NSData>()

    private init() {
        pngDataCache.countLimit = 128
        pngDataCache.totalCostLimit = 4 * 1024 * 1024
    }

    func getIcon(for bundleIdentifier: String) -> NSImage? {
        guard !bundleIdentifier.isEmpty else { return nil }

        if let cachedImage = cache.object(forKey: bundleIdentifier as NSString) {
            return cachedImage
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: bundleIdentifier as NSString)
        return icon
    }

    func iconPNGData(for bundleIdentifier: String, pixelSize: CGFloat = syncedIconPixelSize) -> Data? {
        guard !bundleIdentifier.isEmpty else { return nil }

        let key = "\(bundleIdentifier)-\(Int(pixelSize))" as NSString
        if let cachedData = pngDataCache.object(forKey: key) {
            return cachedData as Data
        }

        guard let icon = getIcon(for: bundleIdentifier) else { return nil }
        guard let data = Self.pngData(from: icon, pixelSize: pixelSize) else { return nil }

        pngDataCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    /// 给只持有 `NSImage` / 没有 bundleID 的调用方使用的辅助路径，
    /// 配 bundleID 时优先走缓存版本以避免每次重复编码。
    func iconPNGData(
        for bundleIdentifier: String?,
        fallbackImage: NSImage?,
        pixelSize: CGFloat = syncedIconPixelSize
    ) -> Data? {
        if let bundleIdentifier, bundleIdentifier.isEmpty == false {
            return iconPNGData(for: bundleIdentifier, pixelSize: pixelSize)
        }
        guard let fallbackImage else { return nil }
        return Self.pngData(from: fallbackImage, pixelSize: pixelSize)
    }

    static func pngData(from image: NSImage, pixelSize: CGFloat = syncedIconPixelSize) -> Data? {
        let targetSize = NSSize(width: pixelSize, height: pixelSize)
        let outputImage = NSImage(size: targetSize)

        outputImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        outputImage.unlockFocus()

        guard let tiffData = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
