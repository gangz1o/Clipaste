import AppKit
import SwiftUI


extension AboutSettingsView {
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
