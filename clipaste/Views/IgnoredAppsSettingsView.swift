import AppKit
import SwiftUI

struct IgnoredAppsSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var selectedIgnoredAppBundleIdentifier: String?

    var body: some View {
        Form {
            ignoredAppsSection
        }
        .settingsPageChrome()
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
}

// MARK: - Section: Ignored Apps

private extension IgnoredAppsSettingsView {
    var ignoredAppsSection: some View {
        Section {
            appListContent
                .frame(minHeight: 280)
        } header: {
            HStack {
                SettingsSectionHeader(title: "Ignored Apps")
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        viewModel.addAppToIgnoreList()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Ignored App")

                    Button {
                        removeSelectedIgnoredApp()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedIgnoredAppBundleIdentifier == nil)
                    .help("Remove Selected Ignored App")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        } footer: {
            SettingsSectionFooter {
                Text("Copied content from the following apps won't be recorded.")
            }
        }
    }

    @ViewBuilder
    var appListContent: some View {
        ZStack {
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

            if viewModel.ignoredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No ignored apps yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Helpers

private extension IgnoredAppsSettingsView {
    func removeSelectedIgnoredApp() {
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
