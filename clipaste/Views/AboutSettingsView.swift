import SwiftUI
import AppKit

struct AboutSettingsView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Clipaste"
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2.weight(.semibold))

                Text("Version \(shortVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Quickly recall, search and re-paste recently copied content.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("App Name") {
                        Text(appName)
                    }

                    LabeledContent("Version") {
                        Text(shortVersion)
                    }

                    LabeledContent("Build") {
                        Text(buildNumber)
                    }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: 340)

            HStack(spacing: 12) {
                Button("System About Panel…") {
                    NSApp.orderFrontStandardAboutPanel()
                }
                .buttonStyle(.bordered)

                Button("Send Feedback") {
                    guard let url = URL(string: "mailto:your_email@example.com?subject=Clipaste%20Feedback") else {
                        return
                    }

                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(32)
    }
}

#Preview {
    AboutSettingsView()
}
