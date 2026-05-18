import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppUpdateViewModel.self) private var updateViewModel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @AppStorage("lastOpenedOfficialWebsiteVersion") private var lastOpenedOfficialWebsiteVersion = ""
    private let telegramURL = URL(string: "https://t.me/clipaste")!
    private let githubURL = URL(string: "https://github.com/gangz1o/Clipaste")!
    private let websiteURL = URL(string: "https://clipaste.com")!
    private let iOSAppStoreURL = URL(string: "https://apps.apple.com/us/app/clipaste-%E5%89%AA%E8%B4%B4%E6%9D%BF%E9%94%AE%E7%9B%98/id6768657055")!
    private let privacyPolicyURL = URL(string: "https://legal.clipaste.com/?page=privacy")!
    private let termsOfServiceURL = URL(string: "https://legal.clipaste.com/?page=terms")!

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

// MARK: - Brand Header

private extension AboutSettingsView {
    var brandSection: some View {
        VStack(spacing: 10) {
            Image(nsImage: appIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

            Text(AppMetadata.displayName)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)

            HStack(spacing: 8) {
                brandIconLink(assetName: "telegram", title: "Telegram", destination: telegramURL)
                brandSeparator
                brandIconLink(assetName: "github", title: "GitHub", destination: githubURL)
                brandSeparator

                HStack(spacing: 4) {
                    Text("Version")
                    Text(verbatim: AppMetadata.displayVersion)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    var appIconImage: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var brandSeparator: some View {
        Text(verbatim: "|")
            .font(.callout)
            .foregroundStyle(.tertiary)
    }

    func brandIconLink(assetName: String, title: LocalizedStringKey, destination: URL) -> some View {
        Link(destination: destination) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

// MARK: - Software Update

private extension AboutSettingsView {
    func softwareUpdateSection(
        viewModel: AppUpdateViewModel,
        automaticallyChecksForUpdates: Binding<Bool>,
        automaticallyDownloadsUpdates: Binding<Bool>
    ) -> some View {
        Section {
            if viewModel.isUpdateAvailable {
                updateStatusBanner(for: viewModel)
            }

            LabeledContent("Current Version") {
                Text(verbatim: viewModel.currentVersion)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let availableUpdate = viewModel.availableUpdate {
                LabeledContent("Latest Version") {
                    Text(verbatim: availableUpdate.version)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Toggle(isOn: automaticallyChecksForUpdates) {
                Text("Automatically Check for Updates")
            }

            Toggle(isOn: automaticallyDownloadsUpdates) {
                Text("Automatically Download Updates")
            }
            .disabled(!viewModel.automaticallyChecksForUpdates)

            HStack(spacing: 12) {
                if viewModel.isUpdateAvailable {
                    Button("Update Now") {
                        viewModel.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCheckingForUpdates || !viewModel.canCheckForUpdates)
                } else {
                    Button("Check for Updates") {
                        viewModel.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCheckingForUpdates || !viewModel.canCheckForUpdates)
                }

                if let releaseNotesURL = viewModel.availableUpdate?.releaseNotesURL {
                    Link("View Release Notes", destination: releaseNotesURL)
                        .buttonStyle(.bordered)
                }

                Spacer()
            }
            .controlSize(.large)

            if let lastUpdateCheckDate = viewModel.lastUpdateCheckDate {
                Text(verbatim: lastCheckedText(for: lastUpdateCheckDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = viewModel.phase {
                Text(verbatim: updateFailureText(message: message))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader(title: "Software Update")
        }
    }
}

// MARK: - Links

private extension AboutSettingsView {
    var linksSection: some View {
        Section {
            Link(destination: iOSAppStoreURL) {
                linkRow(title: "Get iOS Version", systemImage: "iphone")
            }
            .buttonStyle(.plain)

            Button(action: openOfficialWebsite) {
                linkRow(
                    title: "Official Website",
                    systemImage: "globe",
                    showsNewBadge: shouldShowOfficialWebsiteNewBadge
                )
            }
            .buttonStyle(.plain)

            Button(action: sendFeedback) {
                linkRow(title: "Send Feedback", systemImage: "paperplane")
            }
            .buttonStyle(.plain)

            Link(destination: privacyPolicyURL) {
                linkRow(title: "Privacy Policy", systemImage: "lock.doc")
            }
            .buttonStyle(.plain)

            Link(destination: termsOfServiceURL) {
                linkRow(title: "Terms of Service", systemImage: "doc.text")
            }
            .buttonStyle(.plain)
        } header: {
            SettingsSectionHeader(title: "About & Support")
        }
    }

    var shouldShowOfficialWebsiteNewBadge: Bool {
        lastOpenedOfficialWebsiteVersion != AppMetadata.displayVersion
    }

    func linkRow(
        title: LocalizedStringKey,
        systemImage: String,
        showsNewBadge: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            if showsNewBadge {
                newBadge
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    var newBadge: some View {
        Text("New")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(appAccentColor.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(appAccentColor.color.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    .overlay {
                        Capsule()
                            .stroke(appAccentColor.color.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 1)
                    }
            }
    }

    func openOfficialWebsite() {
        lastOpenedOfficialWebsiteVersion = AppMetadata.displayVersion
        NSWorkspace.shared.open(websiteURL)
    }

    func sendFeedback() {
        guard let url = URL(string: "mailto:your_email@example.com?subject=Clipaste%20Feedback") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Status Helpers

private extension AboutSettingsView {
    func updateStatusBanner(for viewModel: AppUpdateViewModel) -> some View {
        HStack(spacing: 12) {
            Label {
                Text(verbatim: updateStatusMessage(for: viewModel))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(updateStatusColor(for: viewModel))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: updateStatusIcon(for: viewModel))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(updateStatusColor(for: viewModel))
            }

            Spacer(minLength: 12)

            if let version = viewModel.availableUpdate?.version, viewModel.isUpdateAvailable {
                updateVersionBadge(version)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(updateStatusBackground(for: viewModel))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(updateStatusBorder(for: viewModel), lineWidth: 1)
                }
        }
    }

    func updateVersionBadge(_ version: String) -> some View {
        let fillColor = appAccentColor.color.opacity(colorScheme == .dark ? 0.18 : 0.08)
        let strokeColor = appAccentColor.color.opacity(colorScheme == .dark ? 0.36 : 0.16)

        return Text(verbatim: version)
            .font(.caption.weight(.semibold))
            .foregroundStyle(appAccentColor.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(fillColor)
                    .overlay {
                        Capsule()
                            .stroke(strokeColor, lineWidth: 1)
                    }
            }
            .accessibilityLabel(Text("Latest Version \(version)"))
    }

    func updateStatusMessage(for viewModel: AppUpdateViewModel) -> String {
        switch viewModel.phase {
        case .idle:
            if !viewModel.automaticallyChecksForUpdates {
                return xcstringsLocalized("Automatic update checks are turned off", locale: locale)
            }
            return xcstringsLocalized("Ready to check for updates", locale: locale)
        case .checking:
            return xcstringsLocalized("Checking for updates", locale: locale)
        case .updateAvailable:
            if let version = viewModel.availableUpdate?.version {
                let format = xcstringsLocalized("A new version is ready: %@", locale: locale)
                return String(format: format, locale: locale, arguments: [version])
            }
            return xcstringsLocalized("A new version is available", locale: locale)
        case .downloading:
            return xcstringsLocalized("Downloading update…", locale: locale)
        case .installing:
            return xcstringsLocalized("Preparing update…", locale: locale)
        case .upToDate:
            return xcstringsLocalized("You're up to date", locale: locale)
        case .failed(let message):
            return updateFailureText(message: message)
        }
    }

    func updateStatusIcon(for viewModel: AppUpdateViewModel) -> String {
        switch viewModel.phase {
        case .idle:
            return viewModel.automaticallyChecksForUpdates ? "arrow.triangle.2.circlepath.circle.fill" : "pause.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .updateAvailable:
            return differentiateWithoutColor ? "arrow.down.circle.fill" : "sparkles"
        case .downloading:
            return "arrow.down.circle.fill"
        case .installing:
            return "shippingbox.circle.fill"
        case .upToDate:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    func updateStatusColor(for viewModel: AppUpdateViewModel) -> Color {
        switch viewModel.phase {
        case .checking, .updateAvailable, .downloading, .installing:
            return appAccentColor.color
        case .failed:
            return .red
        default:
            return .secondary
        }
    }

    func updateStatusBackground(for viewModel: AppUpdateViewModel) -> Color {
        switch viewModel.phase {
        case .checking, .downloading, .installing:
            return appAccentColor.color.opacity(colorScheme == .dark ? 0.16 : 0.07)
        case .updateAvailable:
            return SettingsPalette.cardBackground(for: colorScheme)
        case .failed:
            return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.10)
        default:
            return SettingsPalette.cardBackground(for: colorScheme)
        }
    }

    func updateStatusBorder(for viewModel: AppUpdateViewModel) -> Color {
        switch viewModel.phase {
        case .checking, .downloading, .installing:
            return appAccentColor.color.opacity(colorScheme == .dark ? 0.32 : 0.14)
        case .updateAvailable:
            return .clear
        case .failed:
            return Color.red.opacity(colorScheme == .dark ? 0.34 : 0.22)
        default:
            return SettingsPalette.updateSurfaceBorder(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.9)
        }
    }

    func lastCheckedText(for date: Date) -> String {
        let formattedDate = date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        )
        let format = xcstringsLocalized("Last checked: %@", locale: locale)
        return String(format: format, locale: locale, arguments: [formattedDate])
    }

    func updateFailureText(message: String) -> String {
        let format = xcstringsLocalized("Update check failed: %@", locale: locale)
        return String(format: format, locale: locale, arguments: [message])
    }

    private func xcstringsLocalized(_ key: String, locale: Locale) -> String {
        let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
        return String(localized: resource)
    }
}

#Preview {
    AboutSettingsView()
        .environment(AppUpdateViewModel.preview)
}
