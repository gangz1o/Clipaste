import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject private var storeManager: StoreManager

    private let privacyPolicyURL = URL(string: "https://legal.clipaste.com/?page=privacy")!
    private let termsOfServiceURL = URL(string: "https://legal.clipaste.com/?page=terms")!

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
        ScrollView {
            VStack(spacing: 24) {
                brandSection
                proUpgradeSection
                legalSection
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 34)
            .padding(.top, 38)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var brandSection: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(.rect(cornerRadius: 22))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)

            Text(appName)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)

            Text("\(String(localized: "Version")) \(shortVersion) (\(buildNumber))")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            Text("更快地回顾、搜索及重新粘贴最近复制的内容。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 4)
        }
    }

    private var proUpgradeSection: some View {
        HStack(spacing: 18) {
            shimmeringGlyph

            VStack(alignment: .leading, spacing: 4) {
                Text(storeManager.isProUnlocked ? "Clipaste Pro 已解锁" : storeManager.accessHeadline)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)

                Text(
                    storeManager.isProUnlocked
                    ? "无限历史记录、高级搜索和同步能力都已就绪。"
                    : "一次购买，永久解锁无限历史记录、高级搜索和同步能力。"
                )
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if storeManager.isProUnlocked {
                Text("已解锁")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.5)
                    )
            } else {
                Button("解锁 Pro") {
                    storeManager.presentPaywall(from: .settings)
                }
                .buttonStyle(AboutUpgradeButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color.indigo.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, y: 10)
    }

    private var shimmeringGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.28),
                            Color.indigo.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 34
                    )
                )
                .frame(width: 58, height: 58)
                .blur(radius: 10)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 54, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.6)
                )

            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.indigo
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 2)
        }
    }

    private var legalSection: some View {
        VStack(spacing: 0) {
            Button(action: sendFeedback) {
                actionRowLabel(
                    title: String(localized: "Send Feedback"),
                    systemImage: "paperplane"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            Link(destination: privacyPolicyURL) {
                actionRowLabel(
                    title: "Privacy Policy",
                    systemImage: "lock.doc"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            Link(destination: termsOfServiceURL) {
                actionRowLabel(
                    title: "Terms of Service",
                    systemImage: "doc.text"
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
    }

    private func sendFeedback() {
        guard let url = URL(string: "mailto:your_email@example.com?subject=Clipaste%20Feedback") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func actionRowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
                .labelStyle(.titleAndIcon)

            Spacer(minLength: 12)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct AboutUpgradeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.46, blue: 0.92),
                        Color(red: 0.31, green: 0.62, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
            )
            .shadow(color: Color.accentColor.opacity(configuration.isPressed ? 0.12 : 0.24), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview {
    AboutSettingsView()
        .environmentObject(StoreManager.shared)
}
