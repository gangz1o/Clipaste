import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - iCopy SQLite Engine (Plain Text)

extension MigrationManager {
    nonisolated static func loadICopySQLiteRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readICopySQLiteRows(from: fileURL)
        }.value
    }

    nonisolated static func readICopySQLiteRows(from fileURL: URL) throws -> [MigratedClipboardRow] {
        // Phase 2: WAL-safe temporary copy
        let temporaryFileURL = try copyToTemporaryLocation(from: fileURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }

        let database = try openImmutableDatabase(at: temporaryFileURL)
        defer {
            sqlite3_close_v2(database)
        }

        let detectedGroupColumn = try detectICopyGroupColumn(in: database)
        let sql: String
        if let detectedGroupColumn {
            sql = #"SELECT text, createtime, "\#(detectedGroupColumn)" FROM t_data WHERE text IS NOT NULL;"#
        } else {
            sql = "SELECT text, createtime FROM t_data WHERE text IS NOT NULL;"
        }
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareCode == SQLITE_OK, let statement else {
            throw MigrationError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        var rows: [MigratedClipboardRow] = []

        while true {
            let stepCode = sqlite3_step(statement)

            if stepCode == SQLITE_ROW {
                // Read plain text via sqlite3_column_text
                guard let rawText = sqlite3_column_text(statement, 0) else { continue }
                let text = String(cString: rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { continue }
                let createdAt = decodeSQLiteUnixTimestamp(
                    from: statement,
                    columnIndex: 1
                )
                let rawGroupName = detectedGroupColumn.flatMap { _ in
                    sqlite3_column_text(statement, 2).map { String(cString: $0) }
                }

                rows.append(
                    MigratedClipboardRow(
                        text: text,
                        timestamp: createdAt,
                        sourceAppName: nil,
                        groupName: sanitizeOptionalString(rawGroupName),
                        contentType: inferContentType(from: text)
                    )
                )
                continue
            }

            guard stepCode == SQLITE_DONE else {
                throw MigrationError.rowIterationFailed(String(cString: sqlite3_errmsg(database)))
            }
            break
        }

        return rows
    }
}
