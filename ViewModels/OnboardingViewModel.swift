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
        AccessibilityPermissionCoordinator.openSystemSettings()
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
        // 只写入标志位，AppDelegate 通过 UserDefaults 观察者统一处理
        // activation policy 切换和 onboarding 窗口关闭，避免双重调用产生竞态。
        hasCompletedOnboarding = true
    }

    private func applySharedState(_ updates: () -> Void) {
        isApplyingSharedState = true
        updates()
        isApplyingSharedState = false
    }
}
