import Foundation
import SwiftData
import SwiftUI

struct MigrationView: View {
    private struct ImporterStatus {
        let source: MigrationViewModel.MigrationSource
        let message: LocalizedStringResource
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = MigrationViewModel()
    @State private var isImporterPresented = false
    @State private var importerStatus: ImporterStatus?
    @State private var selectedSource: MigrationViewModel.MigrationSource = .paste

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Data Source", selection: $selectedSource) {
                ForEach(MigrationViewModel.MigrationSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .fixedSize()
            .disabled(viewModel.isMigrating)

            Text(selectedSource.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isMigrating {
                ProgressView()
                    .controlSize(.small)
            }

            if shouldShowStatusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label(
                    title: {
                        if viewModel.isMigrating {
                            Text("Migration in Progress…")
                        } else {
                            Text(selectedSource.fileButtonTitle)
                        }
                    },
                    icon: {
                        Image(systemName: "externaldrive.badge.plus")
                    }
                )
            }
            .disabled(viewModel.isMigrating)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: selectedSource.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .fileDialogDefaultDirectory(defaultDirectoryURL)
        .fileDialogBrowserOptions(fileDialogBrowserOptions)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldShowStatusMessage: Bool {
        if let importerStatus, importerStatus.source == selectedSource {
            return true
        }

        return viewModel.statusSource == selectedSource && viewModel.migrationProgress != nil
    }

    private var statusColor: Color {
        if let importerStatus, importerStatus.source == selectedSource {
            return .red
        }

        return viewModel.isMigrating ? .primary : .secondary
    }

    private var statusMessage: LocalizedStringResource {
        if let importerStatus, importerStatus.source == selectedSource {
            return importerStatus.message
        }

        if viewModel.statusSource == selectedSource,
           let progress = viewModel.migrationProgress {
            return progress
        }

        return selectedSource.idleStatusText
    }

    private var defaultDirectoryURL: URL? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        switch selectedSource {
        case .paste:
            return homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent("com.wiheads.paste", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Paste", isDirectory: true)

        case .iCopy:
            return homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent("cn.better365.iCopy", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)

        case .maccy:
            return homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent("org.p0deje.Maccy", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Maccy", isDirectory: true)

        case .pasteNow:
            return nil
        }
    }

    private var fileDialogBrowserOptions: FileDialogBrowserOptions {
        let source = selectedSource
        return source == .paste || source == .iCopy || source == .maccy ? [.includeHiddenFiles] : []
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            importerStatus = nil
            let source = selectedSource
            Task {
                await viewModel.importData(
                    from: fileURL,
                    source: source,
                    context: modelContext
                )
            }

        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            importerStatus = ImporterStatus(
                source: selectedSource,
                message: LocalizedStringResource("File selection failed: \(error.localizedDescription)")
            )
        }
    }
}
