import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppUpdateViewModel.self) var updateViewModel
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.locale) var locale
    @AppStorage("appAccentColor") var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("lastOpenedOfficialWebsiteVersion") var lastOpenedOfficialWebsiteVersion = ""
    let telegramURL = URL(string: "https://t.me/clipaste")!
    let githubURL = URL(string: "https://github.com/gangz1o/Clipaste")!
    let websiteURL = URL(string: "https://clipaste.com")!
    let iOSAppStoreURL = URL(string: "https://apps.apple.com/us/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055")!
    let privacyPolicyURL = URL(string: "https://legal.clipaste.com/?page=privacy")!
    let termsOfServiceURL = URL(string: "https://legal.clipaste.com/?page=terms")!

    var body: some View {
        @Bindable var updateViewModel = updateViewModel

        VStack(alignment: .leading, spacing: 18) {
            brandSection

            Form {
                softwareUpdateSection(
                    viewModel: updateViewModel,
                    automaticallyChecksForUpdates: $updateViewModel.automaticallyChecksForUpdates,
                    automaticallyDownloadsUpdates: $updateViewModel.automaticallyDownloadsUpdates
                )
                linksSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .settingsScrollChromeHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            updateViewModel.start()
            updateViewModel.refreshAvailabilityIfNeeded()
        }
    }
}
