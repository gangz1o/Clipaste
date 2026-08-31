import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var preferencesStore: AppPreferencesStore
    @AppStorage("appTheme") var appTheme: AppTheme = .system
    @AppStorage("appAccentColor") var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("clipboardLayout") var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("hideMenuBarIcon") var hideMenuBarIcon = false
    @AppStorage("singleClickPaste") var singleClickPaste = false
    @AppStorage("autoPreview") var autoPreview = false

    @State var showingClearAlert = false

    var body: some View {
        Form {
            appearanceSection
            generalSection
            windowSection
            historySection
        }
        .settingsPageChrome()
        .onAppear {
            preferencesStore.refreshLaunchAtLoginStatus()
        }
    }
}
