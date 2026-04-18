import AppKit
import Foundation
import UniformTypeIdentifiers

struct IgnoredAppItem: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage
    let applicationURL: URL?

    var id: String { bundleIdentifier }
}

enum IgnoredAppsServiceError: LocalizedError {
    case invalidApplicationBundle
    case missingBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidApplicationBundle:
            return "The selected item is not a valid application bundle."
        case .missingBundleIdentifier:
            return "The selected application does not contain a bundle identifier."
        }
    }
}

@MainActor
enum IgnoredAppsService {
    static let defaultsKey = "ignoredAppBundleIDs"

    static func loadIgnoredBundleIdentifiers(defaults: UserDefaults = .standard) -> [String] {
        sanitizedBundleIdentifiers(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func ignoredBundleIdentifierSet(defaults: UserDefaults = .standard) -> Set<String> {
        Set(loadIgnoredBundleIdentifiers(defaults: defaults))
    }

    @discardableResult
    static func saveIgnoredBundleIdentifiers(
        _ bundleIdentifiers: [String],
        defaults: UserDefaults = .standard
    ) -> [String] {
        let sanitized = sanitizedBundleIdentifiers(bundleIdentifiers)
        defaults.set(sanitized, forKey: defaultsKey)
        return sanitized
    }

    static func resolveIgnoredApps(
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared
    ) -> [IgnoredAppItem] {
        loadIgnoredBundleIdentifiers(defaults: defaults).map {
            resolvedIgnoredApp(bundleIdentifier: $0, fallbackURL: nil, workspace: workspace)
        }
    }

    @discardableResult
    static func addIgnoredApps(
        from applicationURLs: [URL],
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared
    ) -> (savedBundleIdentifiers: [String], failedApplicationNames: [String]) {
        var identifiers = loadIgnoredBundleIdentifiers(defaults: defaults)
        var failedApplicationNames: [String] = []

        for applicationURL in applicationURLs {
            do {
                let app = try ignoredApp(from: applicationURL, workspace: workspace)
                identifiers.append(app.bundleIdentifier)
            } catch {
                failedApplicationNames.append(applicationURL.deletingPathExtension().lastPathComponent)
            }
        }

        return (
            saveIgnoredBundleIdentifiers(identifiers, defaults: defaults),
            failedApplicationNames
        )
    }

    @discardableResult
    static func removeIgnoredBundleIdentifiers(
        _ bundleIdentifiers: [String],
        defaults: UserDefaults = .standard
    ) -> [String] {
        let removalSet = Set(bundleIdentifiers)
        let remaining = loadIgnoredBundleIdentifiers(defaults: defaults).filter {
            removalSet.contains($0) == false
        }

        return saveIgnoredBundleIdentifiers(remaining, defaults: defaults)
    }

    static func ignoredApp(
        from applicationURL: URL,
        workspace: NSWorkspace = .shared
    ) throws -> IgnoredAppItem {
        let resolvedURL = applicationURL.resolvingSymlinksInPath()

        guard resolvedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw IgnoredAppsServiceError.invalidApplicationBundle
        }

        guard let bundle = Bundle(url: resolvedURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            throw IgnoredAppsServiceError.missingBundleIdentifier
        }

        return resolvedIgnoredApp(
            bundleIdentifier: bundleIdentifier,
            fallbackURL: resolvedURL,
            workspace: workspace
        )
    }

    private static func resolvedIgnoredApp(
        bundleIdentifier: String,
        fallbackURL: URL?,
        workspace: NSWorkspace
    ) -> IgnoredAppItem {
        let applicationURL = fallbackURL ?? workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let bundle = applicationURL.flatMap(Bundle.init(url:))
        let displayName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? applicationURL?.deletingPathExtension().lastPathComponent
            ?? bundleIdentifier

        let icon: NSImage
        if let applicationURL {
            icon = workspace.icon(forFile: applicationURL.path)
        } else {
            let applicationBundleType = UTType(filenameExtension: "app") ?? .applicationBundle
            icon = workspace.icon(for: applicationBundleType)
        }

        return IgnoredAppItem(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            icon: icon,
            applicationURL: applicationURL
        )
    }

    private static func sanitizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        var seen = Set<String>()

        return bundleIdentifiers.compactMap { rawValue in
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            guard seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}
