import AppKit

final class AppIconManager {
    static let shared = AppIconManager()

    static let syncedIconPixelSize: CGFloat = 128

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

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
        guard let icon = getIcon(for: bundleIdentifier) else { return nil }
        return Self.pngData(from: icon, pixelSize: pixelSize)
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
