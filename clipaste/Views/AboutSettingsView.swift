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
        VStack(alignment: .leading, spacing: 14) {
            // Top: Icon & Title
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.15), Color.indigo.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(storeManager.isProUnlocked ? "Clipaste Pro 已解锁" : "Clipaste Pro")
                        .font(.system(size: 15, weight: .bold))
                    Text(storeManager.isProUnlocked ? "核心能力都已就绪。" : "享受 Clipaste Pro 完整体验")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Middle: Core features
            HStack(spacing: 24) {
                featureItem(icon: "paintpalette.fill", text: "多款主题")
                featureItem(icon: "slider.horizontal.3", text: "自定义规则")
                featureItem(icon: "clock.arrow.circlepath", text: "无限历史")
            }
            .padding(.vertical, 4)
            .padding(.leading, 2)
            
            // Bottom: Action Button / Unlocked Badge
            if storeManager.isProUnlocked {
                Text("已解锁")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Button {
                    storeManager.presentPaywall(from: .settings)
                } label: {
                    Text("解锁 Pro 特色")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .shadow(color: Color.accentColor.opacity(0.2), radius: 4, y: 2)
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.1),
                            Color.indigo.opacity(0.03),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

#Preview {
    AboutSettingsView()
        .environmentObject(StoreManager.shared)
}
