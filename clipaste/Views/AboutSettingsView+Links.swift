import AppKit
import SwiftUI


extension AboutSettingsView {
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
