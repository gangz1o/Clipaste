import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcomeAndShortcut
    case permissions
    case preferences
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcomeAndShortcut
    @Published var hasAccessibilityPermission: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isApplyingSharedState, launchAtLogin != oldValue else { return }
            setupLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var historyLimit: HistoryLimit {
        didSet {
            guard !isApplyingSharedState, historyLimit != oldValue else { return }
            preferencesStore.setHistoryLimit(historyLimit)
        }
    }

    private let preferencesStore: AppPreferencesStore
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingSharedState = false

    convenience init() {
        self.init(preferencesStore: AppPreferencesStore.shared)
    }

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        self.launchAtLogin = preferencesStore.launchAtLogin
        self.historyLimit = preferencesStore.historyLimit

        bindPreferences()
        checkPermission()
    }

    func nextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            finishOnboarding()
            return
        }

        currentStep = next
    }

    func checkPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func openSystemSettingsForAccessibility() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    func setupLaunchAtLogin(_ enable: Bool) {
        let currentStatus = SMAppService.mainApp.status == .enabled

        guard currentStatus != enable else {
            preferencesStore.refreshLaunchAtLoginStatus()
            applySharedState {
                launchAtLogin = preferencesStore.launchAtLogin
            }
            return
        }

        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            preferencesStore.refreshLaunchAtLoginStatus()
            applySharedState {
                launchAtLogin = preferencesStore.launchAtLogin
            }
            return
        }

        preferencesStore.refreshLaunchAtLoginStatus()
        applySharedState {
            launchAtLogin = preferencesStore.launchAtLogin
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

        preferencesStore.$historyLimit
            .removeDuplicates()
            .sink { [weak self] limit in
                guard let self else { return }
                self.applySharedState {
                    self.historyLimit = limit
                }
            }
            .store(in: &cancellables)
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true

        DispatchQueue.main.async {
            // 1. 隐藏 Dock 图标，转为纯后台代理模式
            NSApp.setActivationPolicy(.accessory)

            // 2. 找到并关闭当前的引导页窗口
            if let window = NSApplication.shared.windows.first(where: { $0.title == "clipaste" || $0.isKeyWindow }) {
                window.close()
            }
        }
    }

    private func applySharedState(_ updates: () -> Void) {
        isApplyingSharedState = true
        updates()
        isApplyingSharedState = false
    }
}
