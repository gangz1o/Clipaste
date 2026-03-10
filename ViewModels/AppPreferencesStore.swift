import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppPreferencesStore: ObservableObject {
    static let shared = AppPreferencesStore()

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var enableSoundEffects: Bool
    @Published private(set) var historyLimit: HistoryLimit

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchAtLogin = Self.resolveLaunchAtLoginStatus()
        self.enableSoundEffects = defaults.object(forKey: Keys.enableSoundEffects) as? Bool ?? true
        self.historyLimit = HistoryLimit(
            rawValue: defaults.string(forKey: Keys.historyLimit) ?? ""
        ) ?? .unlimited
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = Self.resolveLaunchAtLoginStatus()
    }

    func setLaunchAtLogin(_ enable: Bool) throws {
        let currentStatus = Self.resolveLaunchAtLoginStatus()

        guard currentStatus != enable else {
            launchAtLogin = currentStatus
            return
        }

        if enable {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        refreshLaunchAtLoginStatus()
    }

    func setEnableSoundEffects(_ enable: Bool) {
        guard enableSoundEffects != enable else { return }

        enableSoundEffects = enable
        defaults.set(enable, forKey: Keys.enableSoundEffects)
    }

    func setHistoryLimit(_ limit: HistoryLimit) {
        guard historyLimit != limit else { return }

        historyLimit = limit
        defaults.set(limit.rawValue, forKey: Keys.historyLimit)
    }
}

private extension AppPreferencesStore {
    enum Keys {
        static let enableSoundEffects = "enableSoundEffects"
        static let historyLimit = "historyLimit"
    }

    static func resolveLaunchAtLoginStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
