import AppKit

final class AppIconManager {
    static let shared = AppIconManager()

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
}
