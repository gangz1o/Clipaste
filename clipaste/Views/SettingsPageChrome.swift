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
        HStack(alignment: .top, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
