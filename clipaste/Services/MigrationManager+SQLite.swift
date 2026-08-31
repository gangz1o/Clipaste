import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - WAL-Safe Temporary Copy

extension MigrationManager {
    /// Copies a SQLite database file to `NSTemporaryDirectory()` to sever WAL journal locks
    /// from the original sandbox location. The caller is responsible for deleting the temporary file.
    nonisolated static func copyToTemporaryLocation(from fileURL: URL) throws -> URL {
        let temporaryDirectory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        let temporaryFileName = UUID().uuidString + "-" + fileURL.lastPathComponent
        let temporaryFileURL = temporaryDirectory.appending(path: temporaryFileName)

        do {
            try FileManager.default.copyItem(at: fileURL, to: temporaryFileURL)
        } catch {
            throw MigrationError.temporaryFileCopyFailed(error.localizedDescription)
        }

        return temporaryFileURL
    }

    /// Opens a temporary SQLite copy as an immutable URI so SQLite never tries
    /// to create or read sibling `-wal` / `-shm` files in the app sandbox.
    /// Caller must call `sqlite3_close_v2` when done.
    nonisolated static func openImmutableDatabase(at fileURL: URL) throws -> OpaquePointer {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else {
            throw MigrationError.unableToOpenDatabase("无法构建临时数据库 URI")
        }

        components.queryItems = [
            URLQueryItem(name: "mode", value: "ro"),
            URLQueryItem(name: "immutable", value: "1"),
        ]

        guard let databaseURI = components.string else {
            throw MigrationError.unableToOpenDatabase("无法生成临时数据库 URI")
        }

        var database: OpaquePointer?
        let openCode = sqlite3_open_v2(
            databaseURI,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )

        guard openCode == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let database {
                sqlite3_close_v2(database)
            }
            throw MigrationError.unableToOpenDatabase(message)
        }

        return database
    }
}
