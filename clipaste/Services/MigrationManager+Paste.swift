import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - Paste SQLite Engine (Binary JSON Blob)

extension MigrationManager {
    nonisolated static func loadPasteSQLiteRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readPasteSQLiteRows(from: fileURL)
        }.value
    }

    nonisolated static func readPasteSQLiteRows(from fileURL: URL) throws -> [MigratedClipboardRow] {
        // Phase 2: WAL-safe temporary copy
        let temporaryFileURL = try copyToTemporaryLocation(from: fileURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }

        let database = try openImmutableDatabase(at: temporaryFileURL)
        defer {
            sqlite3_close_v2(database)
        }

        let detectedListTitleColumn = try detectPasteListTitleColumn(in: database)
        let sql: String
        if let detectedListTitleColumn {
            sql = """
            SELECT i.ZRAWPREVIEW, l.\(detectedListTitleColumn), i.ZCREATEDAT
            FROM ZITEMENTITY i
            LEFT JOIN ZLISTENTITY l ON i.ZLIST = l.Z_PK
            WHERE i.ZRAWPREVIEW IS NOT NULL;
            """
        } else {
            sql = """
            SELECT i.ZRAWPREVIEW, NULL, i.ZCREATEDAT
            FROM ZITEMENTITY i
            WHERE i.ZRAWPREVIEW IS NOT NULL;
            """
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
                // Read binary blob from ZRAWPREVIEW column
                guard let blobPointer = sqlite3_column_blob(statement, 0) else { continue }
                let blobLength = Int(sqlite3_column_bytes(statement, 0))
                guard blobLength > 0 else { continue }

                let blobData = Data(bytes: blobPointer, count: blobLength)
                let rawGroupName = sqlite3_column_text(statement, 1).map { String(cString: $0) }
                let createdAt = decodeSQLiteCoreDataReferenceDate(
                    from: statement,
                    columnIndex: 2
                )

                // Deserialize binary JSON
                guard let jsonObject = try? JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                      let typeValue = jsonObject["type"] as? String,
                      typeValue == "text",
                      let textValue = jsonObject["text"] as? String else {
                    continue
                }

                let trimmedText = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedText.isEmpty == false else { continue }

                rows.append(
                    MigratedClipboardRow(
                        text: trimmedText,
                        timestamp: createdAt,
                        sourceAppName: nil,
                        groupName: sanitizeOptionalString(rawGroupName),
                        contentType: inferContentType(from: trimmedText)
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
