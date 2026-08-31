import AppKit
import SwiftUI


extension AboutSettingsView {
    func softwareUpdateSection(
        viewModel: AppUpdateViewModel,
        automaticallyChecksForUpdates: Binding<Bool>,
        automaticallyDownloadsUpdates: Binding<Bool>
    ) -> some View {
        Section {
            if viewModel.isUpdateAvailable {
                updateStatusBanner(for: viewModel)
            }

            LabeledContent("Current Version") {
                Text(verbatim: viewModel.currentVersion)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let availableUpdate = viewModel.availableUpdate {
                LabeledContent("Latest Version") {
                    Text(verbatim: availableUpdate.version)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Toggle(isOn: automaticallyChecksForUpdates) {
                Text("Automatically Check for Updates")
            }

            Toggle(isOn: automaticallyDownloadsUpdates) {
                Text("Automatically Download Updates")
            }
            .disabled(!viewModel.automaticallyChecksForUpdates)

            HStack(spacing: 12) {
                if viewModel.isUpdateAvailable {
                    Button("Update Now") {
                        viewModel.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCheckingForUpdates || !viewModel.canCheckForUpdates)
                } else {
                    Button("Check for Updates") {
                        viewModel.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCheckingForUpdates || !viewModel.canCheckForUpdates)
                }

                if let releaseNotesURL = viewModel.availableUpdate?.releaseNotesURL {
                    Link("View Release Notes", destination: releaseNotesURL)
                        .buttonStyle(.bordered)
                }

                Spacer()
            }
            .controlSize(.large)

            if let lastUpdateCheckDate = viewModel.lastUpdateCheckDate {
                Text(verbatim: lastCheckedText(for: lastUpdateCheckDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = viewModel.phase {
                Text(verbatim: updateFailureText(message: message))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader(title: "Software Update")
        }
    }
}

// MARK: - Links
