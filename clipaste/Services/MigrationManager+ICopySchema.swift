import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - iCopy Schema Inspection

extension MigrationManager {
    nonisolated static func detectICopyGroupColumn(in database: OpaquePointer) throws -> String? {
        let pragmaSQL = "PRAGMA table_info(t_data);"
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

        let nameCandidates = [
            "listName", "list_name",
            "groupName", "group_name",
            "folderName", "folder_name",
            "categoryName", "category_name",
        ]
        let identifierCandidates = [
            "listID", "list_id",
            "groupID", "group_id",
            "folderID", "folder_id",
            "categoryID", "category_id",
        ]
        let columnLookup = Dictionary(uniqueKeysWithValues: availableColumns.map { ($0.lowercased(), $0) })

        for candidate in nameCandidates {
            if let resolvedColumn = columnLookup[candidate.lowercased()] {
                return resolvedColumn
            }
        }

        for candidate in identifierCandidates {
            if let resolvedColumn = columnLookup[candidate.lowercased()] {
                return resolvedColumn
            }
        }

        return nil
    }
}
