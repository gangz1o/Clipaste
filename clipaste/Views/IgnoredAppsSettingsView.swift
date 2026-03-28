import AppKit
import SwiftUI

private struct IgnoredAppsSettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .settingsSectionTitle()

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }
            }

            content
                .liquidGlassCard()
        }
        .padding(.bottom, 16)
    }
}

struct IgnoredAppsSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var selectedIgnoredAppBundleIdentifier: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                ignoredAppsCard
            }
            .padding(20)
        }
        .settingsScrollChromeHidden()
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 440, alignment: .top)
        .onAppear {
            viewModel.reloadIgnoredApps()
        }
        .onChange(of: viewModel.ignoredApps.map(\.bundleIdentifier)) { _, bundleIdentifiers in
            if let selectedIgnoredAppBundleIdentifier,
               bundleIdentifiers.contains(selectedIgnoredAppBundleIdentifier) == false {
                self.selectedIgnoredAppBundleIdentifier = nil
            }
        }
    }

    private var ignoredAppsCard: some View {
        IgnoredAppsSettingsCard(
            title: "Ignored Apps",
            systemImage: "nosign",
            subtitle: "Copied content from the following apps won't be recorded."
        ) {
            VStack(spacing: 12) {
                HStack {
                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            viewModel.addAppToIgnoreList()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 30, height: 24)
                        }
                        .help("Add Ignored App")

                        Button {
                            removeSelectedIgnoredApp()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 30, height: 24)
                        }
                        .disabled(selectedIgnoredAppBundleIdentifier == nil)
                        .help("Remove Selected Ignored App")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ZStack {
                    if viewModel.ignoredApps.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "app.dashed")
                                .font(.title2)
                                .foregroundStyle(.tertiary)

                            Text("No ignored apps yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        List(selection: $selectedIgnoredAppBundleIdentifier) {
                            ForEach(viewModel.ignoredApps) { ignoredApp in
                                HStack(spacing: 12) {
                                    Image(nsImage: ignoredApp.icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 28, height: 28)
                                        .clipShape(.rect(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ignoredApp.displayName)
                                            .font(.body)
                                            .foregroundStyle(.primary)

                                        Text(ignoredApp.bundleIdentifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.vertical, 4)
                                .tag(ignoredApp.bundleIdentifier)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minHeight: 320)
            }
        }
    }

    private func removeSelectedIgnoredApp() {
        guard let selectedIgnoredAppBundleIdentifier,
              let index = viewModel.ignoredApps.firstIndex(where: {
                  $0.bundleIdentifier == selectedIgnoredAppBundleIdentifier
              }) else {
            return
        }

        viewModel.removeAppFromIgnoreList(at: IndexSet(integer: index))
        self.selectedIgnoredAppBundleIdentifier = nil
    }
}

#Preview {
    IgnoredAppsSettingsView()
        .environmentObject(SettingsViewModel())
}
