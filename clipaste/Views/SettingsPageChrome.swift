import SwiftUI

struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.bottom, 4)
    }
}

struct SettingsSectionFooter<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func settingsPageChrome() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .settingsScrollChromeHidden()
            .settingsTopEdgeEffectHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// macOS 26 会在滚动内容延伸到透明标题栏下方时自动绘制 scroll edge effect，
    /// 在设置窗顶部形成一条贯穿窗口的分隔线；该效果不受 NSWindow 的
    /// `titlebarSeparatorStyle` 控制，只能通过 SwiftUI 修饰符隐藏。
    @ViewBuilder
    func settingsTopEdgeEffectHidden() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
