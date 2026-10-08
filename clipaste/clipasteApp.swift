import SwiftUI
import AppKit
import CoreServices
import KeyboardShortcuts
import SwiftData


@main
enum ClipasteMain {
    static func main() {
        #if DEBUG
        // 必须在 clipasteApp 实例化之前执行：App 的存储属性（ClipboardRuntimeStore.shared 等）
        // 早于 init 函数体初始化，放进 init 里时正式库和 iCloud 同步已经被打开。
        // 命中 --initialize-cloudkit-schema 时同步执行并退出,不进入正常启动流程。
        CloudKitSchemaInitializer.runIfRequested()
        #endif
        clipasteApp.main()
    }
}

struct clipasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var preferencesStore = AppPreferencesStore.shared
    @StateObject private var settingsViewModel = SettingsViewModel.shared
    @State private var screenPinViewModel = ScreenPinViewModel.shared
    private let runtimeStore = ClipboardRuntimeStore.shared
    private let appUpdateViewModel = AppUpdateViewModel.shared
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some Scene {
        // Register standard macOS Settings Window
        Settings {
            SettingsView()
                .environmentObject(preferencesStore)
                .environmentObject(settingsViewModel)
                .environment(runtimeStore)
                .environment(screenPinViewModel)
                .modelContainer(runtimeStore.container)
                .environment(\.locale, appLanguage.resolvedLocale)
                .environment(appUpdateViewModel)
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
    }
}
