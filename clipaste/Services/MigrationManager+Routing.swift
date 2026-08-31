import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - Route Dispatch

extension MigrationManager {
    func resolvedAppName(for row: MigratedClipboardRow, source: MigrationSource) -> String {
        if let sourceAppName = Self.sanitizeOptionalString(row.sourceAppName) {
            return sourceAppName
        }

        return source.displayName
    }

    static func resolvedGroupName(for row: MigratedClipboardRow, source: MigrationSource) -> String {
        if let groupName = sanitizeOptionalString(row.groupName) {
            return groupName
        }

        return source.fallbackGroupName
    }

    func migrateFromPasteSQLite(fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await withSecurityScopedAccess(to: fileURL) {
            try await Self.loadPasteSQLiteRows(from: fileURL)
        }
    }

    func migrateFromPasteNowJSON(fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await withSecurityScopedAccess(to: fileURL) {
            try await Self.loadPasteNowJSONRows(from: fileURL)
        }
    }

    func migrateFromICopySQLite(fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await withSecurityScopedAccess(to: fileURL) {
            try await Self.loadICopySQLiteRows(from: fileURL)
        }
    }

    func migrateFromMaccySQLite(fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await withSecurityScopedAccess(to: fileURL) {
            try await Self.loadMaccySQLiteRows(from: fileURL)
        }
    }

    func migrateFromEcoPasteSQLite(fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await withSecurityScopedAccess(to: fileURL) {
            try await Self.loadEcoPasteSQLiteRows(from: fileURL)
        }
    }

    func withSecurityScopedAccess<T>(
        to fileURL: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        guard hasSecurityScope else {
            throw MigrationError.sandboxAccessDenied
        }

        defer {
            fileURL.stopAccessingSecurityScopedResource()
        }

        return try await operation()
    }
}
