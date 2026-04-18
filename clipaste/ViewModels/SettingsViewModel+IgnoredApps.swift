import Foundation

extension SettingsViewModel {
    func addAppsToIgnoreList(from applicationURLs: [URL]) -> [String] {
        guard applicationURLs.isEmpty == false else { return [] }

        let result = IgnoredAppsService.addIgnoredApps(from: applicationURLs)
        reloadIgnoredApps()

        return result.failedApplicationNames
    }

    func removeAppsFromIgnoreList(bundleIdentifiers: Set<String>) {
        guard bundleIdentifiers.isEmpty == false else { return }

        IgnoredAppsService.removeIgnoredBundleIdentifiers(Array(bundleIdentifiers))
        reloadIgnoredApps()
    }

    func reloadIgnoredApps() {
        ignoredApps = IgnoredAppsService.resolveIgnoredApps()
    }
}
