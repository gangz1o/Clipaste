import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: @preconcurrency ObservableObject {
    static let shared = SettingsViewModel()

    let objectWillChange = ObservableObjectPublisher()
    private let preferencesStore: AppPreferencesStore
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingSharedState = false
    var ignoredApps: [IgnoredAppItem] = [] {
        willSet { objectWillChange.send() }
    }

    var launchAtLogin: Bool {
        willSet { objectWillChange.send() }
        didSet {
            guard !isApplyingSharedState, launchAtLogin != oldValue else { return }
            preferencesStore.updateLaunchAtLogin(launchAtLogin)
            applySharedState {
                launchAtLogin = preferencesStore.launchAtLogin
            }
        }
    }

    @AppStorage("appLanguage") var appLanguage: AppLanguage = .auto {
        willSet { objectWillChange.send() }
        didSet { updateAppLanguage(language: appLanguage) }
    }

    @AppStorage("verticalFollowMode") var verticalFollowMode: VerticalFollowMode = .mouse {
        willSet { objectWillChange.send() }
    }

    @AppStorage("historyRetention") var historyRetention: HistoryRetention = .oneMonth {
        willSet { objectWillChange.send() }
    }

    @AppStorage(ModifierKey.quickPasteDefaultsKey) var quickPasteModifier: ModifierKey = .command {
        willSet { objectWillChange.send() }
    }

    @AppStorage(ModifierKey.plainTextDefaultsKey) var plainTextModifier: ModifierKey = .shift {
        willSet { objectWillChange.send() }
    }

    @AppStorage("isCopySoundEnabled") var isCopySoundEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("clipboardLayout") var layoutMode: AppLayoutMode = .horizontal {
        willSet { objectWillChange.send() }
    }

    /// Backward compatibility property - true when layout is vertical or compact
    var isVerticalLayout: Bool {
        layoutMode.isVertical
    }

    @AppStorage("pasteBehavior") var pasteBehavior: PasteBehavior = .direct {
        willSet { objectWillChange.send() }
    }

    @AppStorage("pasteAsPlainText") var pasteAsPlainText: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - 高级：粘贴与行为
    @AppStorage("autoPasteToActiveApp") var autoPasteToActiveApp: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("moveToTopAfterPaste") var moveToTopAfterPaste: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("clearSearchOnPanelActivation") var clearSearchOnPanelActivation: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("requireCmdToDelete") var requireCmdToDelete: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("pasteTextFormat") var pasteTextFormat: PasteTextFormat = .original {
        willSet { objectWillChange.send() }
    }

    @AppStorage("linkDisplayMode") var linkDisplayMode: ClipboardLinkDisplayMode = .rich {
        willSet { objectWillChange.send() }
    }

    @AppStorage("historyLimit") var historyLimit: HistoryLimit = .month {
        willSet { objectWillChange.send() }
    }

    convenience init() {
        self.init(preferencesStore: AppPreferencesStore.shared)
    }

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        self.launchAtLogin = preferencesStore.launchAtLogin

        migrateCopySoundPreferenceIfNeeded()
        ModifierKey.migrateStoredPreferences()
        quickPasteModifier = ModifierKey.quickPastePreference()
        plainTextModifier = ModifierKey.plainTextPreference()
        bindPreferences()
        reloadIgnoredApps()
        preferencesStore.refreshLaunchAtLoginStatus()
        applySharedState {
            launchAtLogin = preferencesStore.launchAtLogin
        }
    }

    func playCopySound() {
        guard isCopySoundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    // MARK: - 语言切换

    private func updateAppLanguage(language: AppLanguage) {
        // 覆盖 AppleLanguages 让 AppKit 层在下次启动时生效
        if language == .auto {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        Task { @MainActor in
            SettingsWindowCoordinator.refreshAllSettingsWindowTitles()
        }
    }

    private func bindPreferences() {
        preferencesStore.$launchAtLogin
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.applySharedState {
                    self.launchAtLogin = isEnabled
                }
            }
            .store(in: &cancellables)
    }

    private func applySharedState(_ updates: () -> Void) {
        isApplyingSharedState = true
        updates()
        isApplyingSharedState = false
    }

    private func migrateCopySoundPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "isCopySoundEnabled") == nil,
              let legacyValue = defaults.object(forKey: "playSound") as? Bool else {
            return
        }

        isCopySoundEnabled = legacyValue
    }
}
