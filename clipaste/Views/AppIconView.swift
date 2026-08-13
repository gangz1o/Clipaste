import AppKit
import SwiftUI

struct AppIconView: View {
    let appBundleID: String?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let icon = resolvedIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "macwindow")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var resolvedIcon: NSImage? {
        AppIconResolver.icon(for: appBundleID) ?? AppIconResolver.clipasteFallbackIcon
    }
}

@MainActor
private enum AppIconResolver {
    static let cache = NSCache<NSString, NSImage>()

    static var clipasteFallbackIcon: NSImage? {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              bundleIdentifier.isEmpty == false else {
            return clipasteFallbackIcon
        }

        if let cached = cache.object(forKey: bundleIdentifier as NSString) {
            return cached
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              applicationDeclaresIcon(at: applicationURL) else {
            return clipasteFallbackIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: bundleIdentifier as NSString)
        return icon
    }

    private static func applicationDeclaresIcon(at applicationURL: URL) -> Bool {
        guard let bundle = Bundle(url: applicationURL) else { return false }

        let stringKeys = ["CFBundleIconFile", "CFBundleIconName"]
        if stringKeys.contains(where: { key in
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return false }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) {
            return true
        }

        if let iconFiles = bundle.object(forInfoDictionaryKey: "CFBundleIconFiles") as? [String],
           iconFiles.contains(where: { $0.isEmpty == false }) {
            return true
        }

        if let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           icons.isEmpty == false {
            return true
        }

        return false
    }
}
