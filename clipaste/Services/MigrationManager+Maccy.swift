import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - Maccy SQLite Engine (Plain Text)

extension MigrationManager {
    nonisolated static func loadMaccySQLiteRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readMaccySQLiteRows(from: fileURL)
        }.value
    }

    nonisolated static func readMaccySQLiteRows(from fileURL: URL) throws -> [MigratedClipboardRow] {
        // Phase 2: WAL-safe temporary copy
        let temporaryFileURL = try copyToTemporaryLocation(from: fileURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }

        let database = try openImmutableDatabase(at: temporaryFileURL)
        defer {
            sqlite3_close_v2(database)
        }

        // Maccy stores text in ZTITLE column of ZHISTORYITEM table
        // Timestamps are in Apple's reference date format (Core Data)
        let sql = """
        SELECT h.ZTITLE, h.ZFIRSTCOPIEDAT, h.ZLASTCOPIEDAT, h.ZAPPLICATION
        FROM ZHISTORYITEM h
        WHERE h.ZTITLE IS NOT NULL
        ORDER BY h.ZFIRSTCOPIEDAT DESC;
        """

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
                // Read text from ZTITLE column
                guard let rawText = sqlite3_column_text(statement, 0) else { continue }
                let text = String(cString: rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { continue }

                // Read timestamp (use ZFIRSTCOPIEDAT as the creation time)
                let createdAt = decodeSQLiteCoreDataReferenceDate(
                    from: statement,
                    columnIndex: 1
                )

                // Read source app name
                let rawAppName: String? = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let sourceAppName = sanitizeOptionalString(rawAppName)

                rows.append(
                    MigratedClipboardRow(
                        text: text,
                        timestamp: createdAt,
                        sourceAppName: sourceAppName,
                        groupName: nil,
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
