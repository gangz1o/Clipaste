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
    }
}

extension View {
    func settingsPageChrome() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .settingsScrollChromeHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
