import AppKit
import SwiftUI

struct PaywallView: View {
    private struct PaywallFeature: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var storeManager: StoreManager

    private let features: [PaywallFeature] = [
        .init(title: "无限历史记录", subtitle: "不再只保留最近 10 条，完整浏览所有剪贴板历史。"),
        .init(title: "高级搜索", subtitle: "即时搜索文本、链接和代码片段，定位更快。"),
        .init(title: "纯文本快捷粘贴", subtitle: "一键去除格式，保持清爽输出。"),
        .init(title: "CloudKit 私有库同步", subtitle: "在同一 Apple ID 的多台 Mac 间同步历史记录。")
    ]

    private var featureColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)
    }

    var body: some View {
        ZStack {
            ambientBackground

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(glassStrokeColor, lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.55), lineWidth: 0.5)
                        .padding(1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 40, y: 20)

            VStack(spacing: 0) {
                topBar
                header
                featureGrid
                footer
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 560)
        .padding(22)
        .onChange(of: storeManager.isProUnlocked) { _, unlocked in
            if unlocked {
                close()
            }
        }
    }

    private var ambientBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.28 : 0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: -170, y: -160)

            Circle()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.24 : 0.2))
                .frame(width: 260, height: 260)
                .blur(radius: 120)
                .offset(x: 185, y: -110)

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 120)
                .offset(x: 120, y: 210)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(glassStrokeColor, lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        VStack(spacing: 16) {
            appIconHero

            VStack(spacing: 7) {
                Text("解锁 Clipaste Pro")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.2)

                Text(storeManager.accessHeadline)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(featureHighlightText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 30)
    }

    private var appIconHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.85),
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 104)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(glassStrokeColor, lineWidth: 0.8)
                )

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 86)
                .clipShape(.rect(cornerRadius: 22))
                .shadow(color: .accentColor.opacity(0.4), radius: 30, x: 0, y: 10)
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: featureColumns, spacing: 14) {
            ForEach(features) { feature in
                featureCard(feature)
            }
        }
        .padding(.bottom, 30)
    }

    private func featureCard(_ feature: PaywallFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.28), radius: 10, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)

                Text(feature.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(featureCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 18, y: 12)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await storeManager.purchasePro()
                }
            } label: {
                HStack(spacing: 10) {
                    if storeManager.isPurchaseInProgress {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    Text(storeManager.purchaseButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(PaywallCTAButtonStyle())
            .disabled(storeManager.isPurchaseInProgress || storeManager.isRestoreInProgress)

            Button {
                Task {
                    await storeManager.restorePurchases()
                }
            } label: {
                HStack(spacing: 8) {
                    if storeManager.isRestoreInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text("恢复购买")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(storeManager.isPurchaseInProgress || storeManager.isRestoreInProgress)

            Text(storeManager.accessFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if let storeErrorMessage = storeManager.storeErrorMessage {
                Text(storeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
    }

    private var featureHighlightText: String {
        if let highlightedFeature = storeManager.highlightedFeature {
            return "继续使用“\(highlightedFeature.title)”需要解锁 Pro。"
        }

        return "一次购买，永久解锁 Clipaste 的全部高级能力。"
    }

    private var glassStrokeColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.34)
    }

    private var featureCardFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }

        return AnyShapeStyle(.thinMaterial)
    }

    private func close() {
        storeManager.dismissPaywall()
        dismiss()
    }
}

private struct PaywallCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.22, blue: 0.55),
                        Color(red: 0.12, green: 0.41, blue: 0.86),
                        Color(red: 0.33, green: 0.67, blue: 0.98)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
            )
            .shadow(color: Color.blue.opacity(configuration.isPressed ? 0.18 : 0.34), radius: 22, y: 14)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    PaywallView()
        .environmentObject(StoreManager.shared)
}
