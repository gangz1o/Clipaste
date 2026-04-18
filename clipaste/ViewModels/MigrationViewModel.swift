import Combine
import Foundation
import SwiftData

@MainActor
final class MigrationViewModel: ObservableObject {
    typealias MigrationSource = MigrationManager.MigrationSource

    @Published var isMigrating: Bool = false
    @Published private(set) var statusSource: MigrationSource?
    @Published var migrationProgress: LocalizedStringResource?

    private let migrationManager: MigrationManager

    init(migrationManager: MigrationManager? = nil) {
        self.migrationManager = migrationManager ?? MigrationManager()
    }

    func importData(from fileURL: URL, source: MigrationSource, context: ModelContext) async {
        guard !isMigrating else { return }

        isMigrating = true
        statusSource = source
        migrationProgress = LocalizedStringResource("Reading \(source.displayName) data…")

        defer {
            isMigrating = false
        }

        do {
            let importedRows = try await migrationManager.loadRows(from: fileURL, source: source)

            guard importedRows.isEmpty == false else {
                migrationProgress = LocalizedStringResource("No importable records were found in the \(source.displayName) file.")
                return
            }

            migrationProgress = LocalizedStringResource("Parsed \(importedRows.count) \(source.displayName) records and writing them into Clipaste…")
            let report = try migrationManager.persistRows(importedRows, source: source, into: context)

            migrationProgress = LocalizedStringResource("\(source.displayName) migration complete: imported \(report.importedCount) items and skipped \(report.skippedCount) duplicates.")
        } catch {
            migrationProgress = LocalizedStringResource("\(source.displayName) migration failed: \(error.localizedDescription)")
        }
    }
}
