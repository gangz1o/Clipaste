import Combine
import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class MigrationManager: ObservableObject {
    enum MigrationSource: String, CaseIterable, Identifiable {
        case paste
        case pasteNow
        case iCopy

        nonisolated var id: String { rawValue }

        nonisolated var displayName: String {
            switch self {
            case .paste:
                "Paste"
            case .pasteNow:
                "PasteNow"
            case .iCopy:
                "iCopy"
            }
        }

        nonisolated var migratedBundleIdentifier: String {
            switch self {
            case .paste:
                "com.wiheads.paste"
            case .pasteNow:
                "app.pastenow.PasteNow"
            case .iCopy:
                "cn.better365.iCopy"
            }
        }

        nonisolated var titleText: String {
            "从 \(displayName) 迁移数据"
        }

        nonisolated var guidanceText: String {
            switch self {
            case .paste:
                "请选择 \(displayName) 的 SQLite 数据库。"
            case .pasteNow:
                "请选择 \(displayName) 导出的 JSON 文件。Clipaste 会按 PasteNow 专用 JSON 路由解析。"
            case .iCopy:
                "请选择 \(displayName) 的 SQLite 数据库。"
            }
        }

        nonisolated var detailText: String {
            switch self {
            case .paste:
                "导入器将使用原生 SQLite3 读取 ZRAWPREVIEW 二进制 JSON，不依赖任何第三方数据库库。"
            case .pasteNow:
                "导入器会读取 JSON 结构中的历史条目，并映射到 Clipaste 的 SwiftData 模型。"
            case .iCopy:
                "导入器将使用原生 SQLite3 读取 t_data 表的纯文本记录，不依赖任何第三方数据库库。"
            }
        }

        nonisolated var fileButtonTitle: String {
            switch self {
            case .paste, .iCopy:
                "选择 SQLite 数据库"
            case .pasteNow:
                "选择 JSON 导出文件"
            }
        }

        nonisolated var idleStatusText: String {
            switch self {
            case .paste:
                "请选择 Paste 的 SQLite 数据库文件。"
            case .pasteNow:
                "请选择 PasteNow 导出的 JSON 文件。"
            case .iCopy:
                "请选择 iCopy 的 SQLite 数据库文件。"
            }
        }

        nonisolated var fallbackGroupName: String {
            switch self {
            case .iCopy:
                "iCopy 导入"
            case .paste, .pasteNow:
                "已导入"
            }
        }

        nonisolated var allowedContentTypes: [UTType] {
            switch self {
            case .paste, .iCopy:
                let sqliteContentTypes = [
                    UTType(filenameExtension: "sqlite"),
                    UTType(filenameExtension: "db"),
                ].compactMap { $0 }
                return sqliteContentTypes.isEmpty ? [.data] : uniqueContentTypes(sqliteContentTypes)
            case .pasteNow:
                return [.json]
            }
        }

        nonisolated private func uniqueContentTypes(_ contentTypes: [UTType]) -> [UTType] {
            contentTypes.reduce(into: [UTType]()) { result, contentType in
                guard result.contains(contentType) == false else { return }
                result.append(contentType)
            }
        }
    }

    @Published var isMigrating: Bool = false
    @Published private(set) var statusSource: MigrationSource?
    @Published var migrationProgress: String = ""

    func importData(from fileURL: URL, source: MigrationSource, context: ModelContext) async {
        guard !isMigrating else { return }

        isMigrating = true
        statusSource = source
        migrationProgress = "正在读取 \(source.displayName) 数据..."

        do {
            let importedRows: [MigratedClipboardRow]

            switch source {
            case .paste:
                importedRows = try await migrateFromPasteSQLite(fileURL: fileURL)
            case .pasteNow:
                importedRows = try await migrateFromPasteNowJSON(fileURL: fileURL)
            case .iCopy:
                importedRows = try await migrateFromICopySQLite(fileURL: fileURL)
            }

            guard importedRows.isEmpty == false else {
                migrationProgress = "\(source.displayName) 文件中没有找到可导入记录。"
                isMigrating = false
                return
            }

            migrationProgress = "已解析 \(importedRows.count) 条 \(source.displayName) 记录，正在写入 Clipaste..."
            let report = try importRows(importedRows, source: source, into: context)

            if report.didMutateStore {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }

            migrationProgress = "\(source.displayName) 迁移完成：导入 \(report.importedCount) 条，跳过 \(report.skippedCount) 条重复记录。"
        } catch {
            migrationProgress = "\(source.displayName) 迁移失败：\(error.localizedDescription)"
        }

        isMigrating = false
    }

    private func importRows(
        _ rows: [MigratedClipboardRow],
        source: MigrationSource,
        into context: ModelContext
    ) throws -> MigrationReport {
        let existingRecords = try context.fetch(FetchDescriptor<ClipboardRecord>())
        let existingGroups = try context.fetch(FetchDescriptor<ClipboardGroupModel>())
        var existingHashes = Set(existingRecords.map(\.contentHash))
        var recordsByHash = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.contentHash, $0) })
        var groupsByNormalizedName = Dictionary(
            uniqueKeysWithValues: existingGroups.map {
                (Self.normalizedGroupLookupKey(for: $0.name), $0)
            }
        )
        var importedCount = 0
        var skippedCount = 0
        var syntheticTimestamp = Date.now
        var nextGroupSortOrder = (existingGroups.map(\.sortOrder).min() ?? 0) - 1
        var didMutateContext = false

        for row in rows {
            let contentHash = CryptoHelper.generateHash(for: row.text)
            let resolvedGroupName = Self.resolvedGroupName(for: row, source: source)
            let knownGroupCount = groupsByNormalizedName.count
            let targetGroup = try resolveGroup(
                named: resolvedGroupName,
                using: context,
                cache: &groupsByNormalizedName,
                nextSortOrder: &nextGroupSortOrder
            )
            if groupsByNormalizedName.count != knownGroupCount {
                didMutateContext = true
            }

            guard existingHashes.insert(contentHash).inserted else {
                if let existingRecord = recordsByHash[contentHash] {
                    didMutateContext = Self.assignGroup(targetGroup.id, to: existingRecord) || didMutateContext
                }
                skippedCount += 1
                continue
            }

            let timestamp: Date
            if let rowTimestamp = row.timestamp {
                timestamp = rowTimestamp
            } else {
                timestamp = syntheticTimestamp
                syntheticTimestamp = syntheticTimestamp.addingTimeInterval(-1)
            }

            let record = ClipboardRecord(
                timestamp: timestamp,
                contentHash: contentHash,
                typeRawValue: row.contentType.rawValue,
                plainText: row.text,
                appBundleID: source.migratedBundleIdentifier,
                appLocalizedName: resolvedAppName(for: row, source: source),
                groupId: targetGroup.id,
                groupIdsRaw: Self.encodedGroupIDs([targetGroup.id])
            )
            context.insert(record)
            recordsByHash[contentHash] = record
            importedCount += 1
            didMutateContext = true
        }

        if didMutateContext {
            try context.save()
        }

        return MigrationReport(
            importedCount: importedCount,
            skippedCount: skippedCount,
            didMutateStore: didMutateContext
        )
    }
}

// MARK: - Internal Types

private extension MigrationManager {
    struct MigrationReport {
        let importedCount: Int
        let skippedCount: Int
        let didMutateStore: Bool
    }

    func resolveGroup(
        named rawGroupName: String,
        using context: ModelContext,
        cache: inout [String: ClipboardGroupModel],
        nextSortOrder: inout Int
    ) throws -> ClipboardGroupModel {
        let normalizedName = Self.normalizedGroupLookupKey(for: rawGroupName)
        if let cachedGroup = cache[normalizedName] {
            return cachedGroup
        }

        var descriptor = FetchDescriptor<ClipboardGroupModel>(
            predicate: #Predicate<ClipboardGroupModel> { group in
                group.name == rawGroupName
            }
        )
        descriptor.fetchLimit = 1

        if let existingGroup = try context.fetch(descriptor).first {
            cache[normalizedName] = existingGroup
            return existingGroup
        }

        let createdGroup = ClipboardGroupModel(
            name: rawGroupName,
            systemIconName: "folder",
            sortOrder: nextSortOrder
        )
        nextSortOrder -= 1
        context.insert(createdGroup)
        cache[normalizedName] = createdGroup
        return createdGroup
    }

    struct MigratedClipboardRow: Sendable {
        let text: String
        let timestamp: Date?
        let sourceAppName: String?
        let groupName: String?
        let contentType: ClipboardContentType
    }

    struct JSONExtractorConfiguration: Sendable {
        let collectionKeys: Set<String>
        let textKeys: [String]
        let dateKeys: [String]
        let appNameKeys: [String]
        let groupNameKeys: [String]
    }

    enum MigrationError: LocalizedError {
        case sandboxAccessDenied
        case unableToOpenDatabase(String)
        case statementPreparationFailed(String)
        case rowIterationFailed(String)
        case temporaryFileCopyFailed(String)
        case unableToReadJSON(String)
        case jsonParsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .sandboxAccessDenied:
                "沙盒授权失败，无法读取所选文件"
            case .unableToOpenDatabase(let message):
                "无法打开数据库：\(message)"
            case .statementPreparationFailed(let message):
                "SQLite 查询准备失败：\(message)"
            case .rowIterationFailed(let message):
                "SQLite 遍历结果集失败：\(message)"
            case .temporaryFileCopyFailed(let message):
                "临时文件拷贝失败：\(message)"
            case .unableToReadJSON(let message):
                "无法读取 JSON 文件：\(message)"
            case .jsonParsingFailed(let message):
                "JSON 解析失败：\(message)"
            }
        }
    }
}

// MARK: - Route Dispatch

private extension MigrationManager {
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

// MARK: - WAL-Safe Temporary Copy

private extension MigrationManager {
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

// MARK: - Paste SQLite Engine (Binary JSON Blob)

private extension MigrationManager {
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

        let sql = """
        SELECT i.ZRAWPREVIEW, l.ZTITLE
        FROM ZITEMENTITY i
        LEFT JOIN ZLISTENTITY l ON i.ZLIST = l.Z_PK
        WHERE i.ZRAWPREVIEW IS NOT NULL;
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
        var syntheticTimestamp = Date.now

        while true {
            let stepCode = sqlite3_step(statement)

            if stepCode == SQLITE_ROW {
                // Read binary blob from ZRAWPREVIEW column
                guard let blobPointer = sqlite3_column_blob(statement, 0) else { continue }
                let blobLength = Int(sqlite3_column_bytes(statement, 0))
                guard blobLength > 0 else { continue }

                let blobData = Data(bytes: blobPointer, count: blobLength)
                let rawGroupName = sqlite3_column_text(statement, 1).map { String(cString: $0) }

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
                        timestamp: syntheticTimestamp,
                        sourceAppName: nil,
                        groupName: sanitizeOptionalString(rawGroupName),
                        contentType: inferContentType(from: trimmedText)
                    )
                )
                syntheticTimestamp = syntheticTimestamp.addingTimeInterval(-1)
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

// MARK: - iCopy SQLite Engine (Plain Text)

private extension MigrationManager {
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
            sql = #"SELECT text, "\#(detectedGroupColumn)" FROM t_data WHERE text IS NOT NULL;"#
        } else {
            sql = "SELECT text FROM t_data WHERE text IS NOT NULL;"
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
        var syntheticTimestamp = Date.now

        while true {
            let stepCode = sqlite3_step(statement)

            if stepCode == SQLITE_ROW {
                // Read plain text via sqlite3_column_text
                guard let rawText = sqlite3_column_text(statement, 0) else { continue }
                let text = String(cString: rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { continue }
                let rawGroupName = detectedGroupColumn.flatMap { _ in
                    sqlite3_column_text(statement, 1).map { String(cString: $0) }
                }

                rows.append(
                    MigratedClipboardRow(
                        text: text,
                        timestamp: syntheticTimestamp,
                        sourceAppName: nil,
                        groupName: sanitizeOptionalString(rawGroupName),
                        contentType: inferContentType(from: text)
                    )
                )
                syntheticTimestamp = syntheticTimestamp.addingTimeInterval(-1)
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

// MARK: - PasteNow JSON Engine (Preserved)

private extension MigrationManager {
    nonisolated static func loadPasteNowJSONRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readJSONRows(
                from: fileURL,
                configuration: JSONExtractorConfiguration(
                    collectionKeys: ["items", "clips", "history", "histories", "records", "data", "clipboard", "list"],
                    textKeys: ["text", "content", "value", "cliptext", "plaintext", "memo"],
                    dateKeys: [],
                    appNameKeys: appNameKeyCandidates,
                    groupNameKeys: ["listname"]
                )
            )
        }.value
    }

    nonisolated static func readJSONRows(
        from fileURL: URL,
        configuration: JSONExtractorConfiguration
    ) throws -> [MigratedClipboardRow] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MigrationError.unableToReadJSON(error.localizedDescription)
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MigrationError.jsonParsingFailed(error.localizedDescription)
        }

        var rows: [MigratedClipboardRow] = []
        collectJSONRows(
            from: jsonObject,
            configuration: configuration,
            inheritedGroupName: nil,
            into: &rows
        )
        return rows
    }

    nonisolated static func collectJSONRows(
        from jsonObject: Any,
        configuration: JSONExtractorConfiguration,
        inheritedGroupName: String?,
        into rows: inout [MigratedClipboardRow]
    ) {
        switch jsonObject {
        case let array as [Any]:
            for element in array {
                collectJSONRows(
                    from: element,
                    configuration: configuration,
                    inheritedGroupName: inheritedGroupName,
                    into: &rows
                )
            }

        case let dictionary as [String: Any]:
            let resolvedGroupName = firstStringValue(
                in: dictionary,
                matching: Set(configuration.groupNameKeys)
            ).flatMap(sanitizeOptionalString(_:)) ?? inheritedGroupName

            if let row = makeJSONRow(
                from: dictionary,
                configuration: configuration,
                inheritedGroupName: resolvedGroupName
            ) {
                rows.append(row)
            }

            for (key, value) in dictionary {
                let normalizedKey = key.lowercased()
                guard configuration.collectionKeys.contains(normalizedKey)
                        || value is [Any]
                        || value is [String: Any] else {
                    continue
                }

                collectJSONRows(
                    from: value,
                    configuration: configuration,
                    inheritedGroupName: resolvedGroupName,
                    into: &rows
                )
            }

        default:
            break
        }
    }

    nonisolated static func makeJSONRow(
        from dictionary: [String: Any],
        configuration: JSONExtractorConfiguration,
        inheritedGroupName: String?
    ) -> MigratedClipboardRow? {
        let normalizedDictionary = dictionary.reduce(into: [String: Any]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }

        guard let text = configuration.textKeys
            .compactMap({ normalizedDictionary[$0] as? String })
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.isEmpty == false }) else {
            return nil
        }

        let timestamp = configuration.dateKeys
            .compactMap({ normalizedDictionary[$0] })
            .compactMap(decodeJSONDate(_:))
            .first ?? Date.now
        let sourceAppName = firstStringValue(
            in: dictionary,
            matching: Set(configuration.appNameKeys)
        ).flatMap(sanitizeOptionalString(_:))
        let groupName = firstStringValue(
            in: dictionary,
            matching: Set(configuration.groupNameKeys)
        ).flatMap(sanitizeOptionalString(_:)) ?? inheritedGroupName

        return MigratedClipboardRow(
            text: text,
            timestamp: configuration.dateKeys.isEmpty ? nil : timestamp,
            sourceAppName: sourceAppName,
            groupName: groupName,
            contentType: inferContentType(from: text)
        )
    }
}

// MARK: - JSON Date Decoding

private extension MigrationManager {
    nonisolated static func decodeJSONDate(_ value: Any) -> Date? {
        switch value {
        case let number as NSNumber:
            return decodeJSONNumericDate(number.doubleValue)

        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }

            if let numeric = Double(trimmed) {
                return decodeJSONNumericDate(numeric)
            }

            let iso8601Formatter = ISO8601DateFormatter()
            if let date = iso8601Formatter.date(from: trimmed) {
                return date
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: trimmed)

        default:
            return nil
        }
    }

    nonisolated static func decodeJSONNumericDate(_ rawValue: Double) -> Date {
        if rawValue > 1_000_000_000_000 || rawValue < -1_000_000_000_000 {
            Date(timeIntervalSince1970: rawValue / 1000)
        } else {
            Date(timeIntervalSince1970: rawValue)
        }
    }
}

// MARK: - String Utilities

private extension MigrationManager {
    nonisolated static func firstStringValue(
        in jsonObject: Any,
        matching keys: Set<String>
    ) -> String? {
        switch jsonObject {
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                if keys.contains(key.lowercased()), let stringValue = value as? String {
                    return stringValue
                }
            }

            for value in dictionary.values {
                if let nestedValue = firstStringValue(in: value, matching: keys) {
                    return nestedValue
                }
            }

        case let array as [Any]:
            for value in array {
                if let nestedValue = firstStringValue(in: value, matching: keys) {
                    return nestedValue
                }
            }

        default:
            break
        }

        return nil
    }

    nonisolated static func sanitizeOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }

        return trimmed
    }

    nonisolated static var appNameKeyCandidates: [String] {
        [
            "appname",
            "app_name",
            "applicationname",
            "application_name",
            "sourcename",
            "source_name",
            "sourceappname",
            "source_app_name",
            "applocalizedname",
            "app_localized_name",
        ]
    }

    nonisolated static func normalizedGroupLookupKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func assignGroup(_ groupID: String, to record: ClipboardRecord) -> Bool {
        var groupIDs = decodedGroupIDs(primaryGroupID: record.groupId, rawGroupIDs: record.groupIdsRaw)
        guard groupIDs.contains(groupID) == false else {
            return false
        }
        groupIDs.append(groupID)
        record.groupId = groupIDs.first
        record.groupIdsRaw = encodedGroupIDs(groupIDs)
        return true
    }

    nonisolated static func decodedGroupIDs(primaryGroupID: String?, rawGroupIDs: String?) -> [String] {
        var result: [String] = []

        if let primaryGroupID, !primaryGroupID.isEmpty {
            result.append(primaryGroupID)
        }

        if let rawGroupIDs,
           let data = rawGroupIDs.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            for groupID in decoded where !groupID.isEmpty && result.contains(groupID) == false {
                result.append(groupID)
            }
        }

        return result
    }

    nonisolated static func encodedGroupIDs(_ groupIDs: [String]) -> String? {
        let cleaned = groupIDs.reduce(into: [String]()) { result, groupID in
            guard !groupID.isEmpty, result.contains(groupID) == false else { return }
            result.append(groupID)
        }

        guard !cleaned.isEmpty,
              let data = try? JSONEncoder().encode(cleaned),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }

        return raw
    }

    nonisolated static func inferContentType(from text: String) -> ClipboardContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return .link
        }

        return .text
    }
}

// MARK: - iCopy Schema Inspection

private extension MigrationManager {
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
