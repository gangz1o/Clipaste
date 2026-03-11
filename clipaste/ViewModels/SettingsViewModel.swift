import SwiftUI
import Combine
import ServiceManagement

final class SettingsViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        willSet { objectWillChange.send() }
        didSet { toggleLaunchAtLogin(enabled: launchAtLogin) }
    }

    @AppStorage("appLanguage") var appLanguage: AppLanguage = .auto {
        willSet { objectWillChange.send() }
        didSet { updateAppLanguage(language: appLanguage) }
    }

    @AppStorage("isVerticalLayout") var isVerticalLayout: Bool = false {
        willSet { objectWillChange.send() }
        didSet {
            // 保持 clipboardLayout 与 isVerticalLayout 同步
            layoutMode = isVerticalLayout ? .vertical : .horizontal
            NotificationCenter.default.post(
                name: .clipboardLayoutModeChanged,
                object: isVerticalLayout ? AppLayoutMode.vertical : AppLayoutMode.horizontal
            )
        }
    }

    @AppStorage("verticalFollowMode") var verticalFollowMode: VerticalFollowMode = .mouse {
        willSet { objectWillChange.send() }
    }

    @AppStorage("historyRetention") var historyRetention: HistoryRetention = .oneMonth {
        willSet { objectWillChange.send() }
    }

    @AppStorage("playSound") var playSound: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("clipboardLayout") var layoutMode: AppLayoutMode = .horizontal {
        willSet { objectWillChange.send() }
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

    @AppStorage("pasteTextFormat") var pasteTextFormat: PasteTextFormat = .original {
        willSet { objectWillChange.send() }
    }

    @AppStorage("historyLimit") var historyLimit: HistoryLimit = .month {
        willSet { objectWillChange.send() }
    }


    init() {
        // 冷启动时：强制同步系统真实的开机自启状态
        // 防止用户在系统设置里单方面关掉后 Toggle 状态与实际不一致
        let isRegistered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }
    }

    // MARK: - 开机自启

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
                print("✅ 成功注册开机自启")
            } else {
                try SMAppService.mainApp.unregister()
                print("✅ 成功取消开机自启")
            }
        } catch {
            print("❌ 开机自启状态修改失败: \(error)")
            // 底层调用失败时，将 UI 回滚到系统真实状态
            DispatchQueue.main.async {
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
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
    }
}
