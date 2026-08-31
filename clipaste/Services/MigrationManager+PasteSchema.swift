import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - Paste Schema Inspection

extension MigrationManager {
    nonisolated static func detectPasteListTitleColumn(in database: OpaquePointer) throws -> String? {
        // Check if ZLISTENTITY table exists at all
        let tableCheckSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='ZLISTENTITY';"
        var tableCheckStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, tableCheckSQL, -1, &tableCheckStatement, nil) == SQLITE_OK,
              let tableCheckStatement else {
            return nil
        }
        defer { sqlite3_finalize(tableCheckStatement) }
        guard sqlite3_step(tableCheckStatement) == SQLITE_ROW else { return nil }

        let pragmaSQL = "PRAGMA table_info(ZLISTENTITY);"
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(database, pragmaSQL, -1, &statement, nil)

        guard prepareCode == SQLITE_OK, let statement else {
            throw MigrationError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        var availableColumns: [String] = []

        while true {
            let stepCode = sqlite3_step(statement)

            if stepCode == SQLITE_ROW {
                guard let rawColumnName = sqlite3_column_text(statement, 1) else { continue }
                availableColumns.append(String(cString: rawColumnName))
                continue
            }

            guard stepCode == SQLITE_DONE else {
                throw MigrationError.rowIterationFailed(String(cString: sqlite3_errmsg(database)))
            }
            break
        }

        let titleCandidates = ["ZTITLE", "ZNAME", "ZLABEL", "ZDISPLAYNAME", "ZTAG"]
        let columnLookup = Dictionary(uniqueKeysWithValues: availableColumns.map { ($0.uppercased(), $0) })

        for candidate in titleCandidates {
            if let resolvedColumn = columnLookup[candidate] {
                return resolvedColumn
            }
        }

        return nil
    }
}
