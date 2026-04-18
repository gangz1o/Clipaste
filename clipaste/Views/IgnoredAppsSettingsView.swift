import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct IgnoredAppsSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var isImporterPresented = false
    @State private var isImportErrorPresented = false
    @State private var importErrorMessage: LocalizedStringResource?
    @State private var selectedIgnoredAppBundleIdentifiers = Set<String>()

    var body: some View {
        Form {
            ignoredAppsSection
        }
        .settingsPageChrome()
        .onAppear {
            viewModel.reloadIgnoredApps()
        }
        .onChange(of: viewModel.ignoredApps.map(\.bundleIdentifier)) { _, bundleIdentifiers in
            selectedIgnoredAppBundleIdentifiers.formIntersection(Set(bundleIdentifiers))
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType.applicationBundle],
            allowsMultipleSelection: true,
            onCompletion: handleImportSelection
        )
        .fileDialogDefaultDirectory(defaultDirectoryURL)
        .onDeleteCommand(perform: removeSelectedIgnoredApps)
        .alert("Unable to Add Apps", isPresented: $isImportErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            if let importErrorMessage {
                Text(importErrorMessage)
            }
        }
    }
}

// MARK: - Section: Ignored Apps

private extension IgnoredAppsSettingsView {
    var ignoredAppsSection: some View {
        Section {
            IgnoredAppsListView(
                ignoredApps: viewModel.ignoredApps,
                selection: $selectedIgnoredAppBundleIdentifiers
            )
                .frame(minHeight: 280)
        } header: {
            HStack {
                SettingsSectionHeader(title: "Ignored Apps")
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Add Ignored Apps", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .help("Add Ignored Apps")

                    Button {
                        removeSelectedIgnoredApps()
                    } label: {
                        Label("Remove Selected Ignored Apps", systemImage: "minus")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedIgnoredAppBundleIdentifiers.isEmpty)
                    .help("Remove Selected Ignored Apps")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        } footer: {
            SettingsSectionFooter {
                Text("Copied content from the apps above won't be recorded. You can select multiple apps and remove them together.")
            }
        }
    }
}

// MARK: - Helpers

private extension IgnoredAppsSettingsView {
    var defaultDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(filePath: "/Applications", directoryHint: .isDirectory)
    }

    func removeSelectedIgnoredApps() {
        let selectedBundleIdentifiers = selectedIgnoredAppBundleIdentifiers
        guard selectedBundleIdentifiers.isEmpty == false else { return }

        viewModel.removeAppsFromIgnoreList(bundleIdentifiers: selectedBundleIdentifiers)
        selectedIgnoredAppBundleIdentifiers.removeAll()
    }

    func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let applicationURLs):
            guard applicationURLs.isEmpty == false else { return }

            let failedApplicationNames = viewModel.addAppsToIgnoreList(from: applicationURLs)
            if failedApplicationNames.isEmpty == false {
                let failedApplicationList = failedApplicationNames.joined(separator: ", ")
                presentImportError(
                    message: LocalizedStringResource("Some apps couldn't be added: \(failedApplicationList).")
                )
            }

        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            presentImportError(
                message: LocalizedStringResource("App selection failed: \(error.localizedDescription)")
            )
        }
    }

    func presentImportError(message: LocalizedStringResource) {
        importErrorMessage = message
        isImportErrorPresented = true
    }
}

#Preview {
    IgnoredAppsSettingsView()
        .environmentObject(SettingsViewModel())
}
