import AppKit
import SwiftUI


extension AboutSettingsView {
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
