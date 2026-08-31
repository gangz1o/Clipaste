import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - EcoPaste SQLite Engine (Plain Text)

extension MigrationManager {
    nonisolated static func loadEcoPasteSQLiteRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readEcoPasteSQLiteRows(from: fileURL)
        }.value
    }

    nonisolated static func readEcoPasteSQLiteRows(from fileURL: URL) throws -> [MigratedClipboardRow] {
        let temporaryFileURL = try copyToTemporaryLocation(from: fileURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }

        let database = try openImmutableDatabase(at: temporaryFileURL)
        defer {
            sqlite3_close_v2(database)
        }

        // EcoPaste's `history` table covers text/html/rtf/files/image. We import
        // everything except image: for html/rtf the `value` is markup while
        // `search` carries the stripped plain text; for files `value` is a
        // JSON-encoded path array and `search` is the human-readable form.
        let sql = #"""
        SELECT type, value, search, createTime
        FROM history
        WHERE type IN ('text', 'html', 'rtf', 'files')
        ORDER BY createTime DESC;
        """#

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
                let rawType = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let rawValue = sqlite3_column_text(statement, 1).map { String(cString: $0) }
                let rawSearch = sqlite3_column_text(statement, 2).map { String(cString: $0) }

                let plainText: String
                switch rawType.lowercased() {
                case "text":
                    plainText = sanitizeOptionalString(rawValue)
                        ?? sanitizeOptionalString(rawSearch)
                        ?? ""
                case "files":
                    plainText = sanitizeOptionalString(rawSearch)
                        ?? decodeEcoPasteFilesValue(rawValue)
                        ?? ""
                default:
                    // html / rtf — `search` is the stripped plain-text version
                    // EcoPaste populates; markup-only `value` is not useful for
                    // a text clipboard entry, so we skip when search is empty.
                    plainText = sanitizeOptionalString(rawSearch) ?? ""
                }

                guard plainText.isEmpty == false else { continue }

                let createdAt = decodeEcoPasteTimestamp(
                    from: statement,
                    columnIndex: 3
                )

                rows.append(
                    MigratedClipboardRow(
                        text: plainText,
                        timestamp: createdAt,
                        sourceAppName: nil,
                        groupName: nil,
                        contentType: inferContentType(from: plainText)
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

    /// EcoPaste persists `createTime` as a dayjs-formatted `YYYY-MM-DD HH:mm:ss`
    /// string in the device's local timezone. Fall back to the numeric decoders
    /// in case a future build switches to epoch storage.
    nonisolated static func decodeEcoPasteTimestamp(
        from statement: OpaquePointer,
        columnIndex: Int32
    ) -> Date? {
        guard sqlite3_column_type(statement, columnIndex) != SQLITE_NULL else {
            return nil
        }

        if sqlite3_column_type(statement, columnIndex) == SQLITE_TEXT,
           let rawValue = sqlite3_column_text(statement, columnIndex) {
            let raw = String(cString: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = ecoPasteDateFormatter.date(from: raw) {
                return parsed
            }
            return decodeUnixTimestamp(raw)
        }

        return decodeSQLiteUnixTimestamp(from: statement, columnIndex: columnIndex)
    }

    /// EcoPaste serializes `files`-type entries as a JSON array of absolute
    /// paths (e.g. `["/Users/x/a.txt","/Users/x/b.png"]`). When the prepared
    /// `search` column is empty we still want to surface those paths as
    /// newline-joined text so the entry survives the import.
    nonisolated static func decodeEcoPasteFilesValue(_ rawValue: String?) -> String? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let paths: [String]
        switch decoded {
        case let array as [String]:
            paths = array
        case let array as [Any]:
            paths = array.compactMap { $0 as? String }
        default:
            return nil
        }

        let joined = paths
            .compactMap { sanitizeOptionalString($0) }
            .joined(separator: "\n")
        return sanitizeOptionalString(joined)
    }

    nonisolated static let ecoPasteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
