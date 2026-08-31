import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class MigrationManager {
    enum MigrationSource: String, CaseIterable, Identifiable {
        case paste
        case pasteNow
        case iCopy
        case maccy
        case ecoPaste

        nonisolated var id: String { rawValue }

        nonisolated var displayName: String {
            switch self {
            case .paste:
                "Paste"
            case .pasteNow:
                "PasteNow"
            case .iCopy:
                "iCopy"
            case .maccy:
                "Maccy"
            case .ecoPaste:
                "EcoPaste"
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
            case .maccy:
                "org.p0deje.Maccy"
            case .ecoPaste:
                "com.ayangweb.EcoPaste"
            }
        }

        nonisolated var titleText: LocalizedStringResource {
            LocalizedStringResource("从 \(displayName) 迁移数据")
        }

        nonisolated var summaryText: LocalizedStringResource {
            switch self {
            case .paste:
                LocalizedStringResource("Choose the Paste SQLite database file. Clipaste will import the history records into your current library.")
            case .pasteNow:
                LocalizedStringResource("Choose the PasteNow exported JSON file. Clipaste will parse the history items and import them into your current library.")
            case .iCopy:
                LocalizedStringResource("Choose the iCopy SQLite database file. Clipaste will import the text history into your current library.")
            case .maccy:
                LocalizedStringResource("Choose the Maccy SQLite database file. Clipaste will import the text history into your current library.")
            case .ecoPaste:
                LocalizedStringResource("Choose the EcoPaste SQLite database file. Clipaste will import the text history into your current library.")
            }
        }

        nonisolated var guidanceText: LocalizedStringResource {
            switch self {
            case .paste:
                LocalizedStringResource("请选择 \(displayName) 的 SQLite 数据库。")
            case .pasteNow:
                LocalizedStringResource("请选择 \(displayName) 导出的 JSON 文件。Clipaste 会按 PasteNow 专用 JSON 路由解析。")
            case .iCopy:
                LocalizedStringResource("请选择 \(displayName) 的 SQLite 数据库。")
            case .maccy:
                LocalizedStringResource("请选择 \(displayName) 的 SQLite 数据库。")
            case .ecoPaste:
                LocalizedStringResource("请选择 \(displayName) 的 SQLite 数据库。")
            }
        }

        nonisolated var detailText: LocalizedStringResource {
            switch self {
            case .paste:
                LocalizedStringResource("导入器将使用原生 SQLite3 读取 ZRAWPREVIEW 二进制 JSON，不依赖任何第三方数据库库。")
            case .pasteNow:
                LocalizedStringResource("导入器会读取 JSON 结构中的历史条目，并映射到 Clipaste 的 SwiftData 模型。")
            case .iCopy:
                LocalizedStringResource("导入器将使用原生 SQLite3 读取 t_data 表的纯文本记录，不依赖任何第三方数据库库。")
            case .maccy:
                LocalizedStringResource("导入器将使用原生 SQLite3 读取 ZHISTORYITEM 表的文本记录，不依赖任何第三方数据库库。")
            case .ecoPaste:
                LocalizedStringResource("导入器将使用原生 SQLite3 读取 history 表的文本记录，不依赖任何第三方数据库库。")
            }
        }

        nonisolated var fileButtonTitle: LocalizedStringResource {
            switch self {
            case .paste, .iCopy, .maccy, .ecoPaste:
                LocalizedStringResource("Select SQLite Database")
            case .pasteNow:
                LocalizedStringResource("Select JSON Export File")
            }
        }

        nonisolated var idleStatusText: LocalizedStringResource {
            switch self {
            case .paste:
                LocalizedStringResource("Select the Paste SQLite database file.")
            case .pasteNow:
                LocalizedStringResource("Select the PasteNow exported JSON file.")
            case .iCopy:
                LocalizedStringResource("Select the iCopy SQLite database file.")
            case .maccy:
                LocalizedStringResource("Select the Maccy SQLite database file.")
            case .ecoPaste:
                LocalizedStringResource("Select the EcoPaste SQLite database file.")
            }
        }

        nonisolated var fallbackGroupName: String {
            switch self {
            case .iCopy:
                "iCopy 导入"
            case .maccy:
                "Maccy 导入"
            case .ecoPaste:
                "EcoPaste 导入"
            case .paste, .pasteNow:
                "已导入"
            }
        }

        nonisolated var allowedContentTypes: [UTType] {
            switch self {
            case .paste, .iCopy, .maccy, .ecoPaste:
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

    func loadRows(from fileURL: URL, source: MigrationSource) async throws -> [MigratedClipboardRow] {
        switch source {
        case .paste:
            try await migrateFromPasteSQLite(fileURL: fileURL)
        case .pasteNow:
            try await migrateFromPasteNowJSON(fileURL: fileURL)
        case .iCopy:
            try await migrateFromICopySQLite(fileURL: fileURL)
        case .maccy:
            try await migrateFromMaccySQLite(fileURL: fileURL)
        case .ecoPaste:
            try await migrateFromEcoPasteSQLite(fileURL: fileURL)
        }
    }

    func persistRows(
        _ rows: [MigratedClipboardRow],
        source: MigrationSource,
        into context: ModelContext
    ) throws -> MigrationReport {
        let existingRecords = try context.fetch(FetchDescriptor<ClipboardRecord>())
        let existingGroups = try context.fetch(FetchDescriptor<ClipboardGroupModel>())
        var existingHashes = Set(existingRecords.map(\.contentHash))
        var recordsByHash = Dictionary(existingRecords.map { ($0.contentHash, $0) }, uniquingKeysWith: { first, _ in first })
        var groupsByNormalizedName = Dictionary(
            existingGroups.map { (Self.normalizedGroupLookupKey(for: $0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var importedCount = 0
        var skippedCount = 0
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
                    if let migratedTimestamp = row.timestamp, migratedTimestamp > existingRecord.timestamp {
                        existingRecord.timestamp = migratedTimestamp
                        didMutateContext = true
                    }
                }
                skippedCount += 1
                continue
            }

            let storedText = ClipboardTextSyncPolicy.storedTextUsingPreferences(for: row.text)
            let record = ClipboardRecord(
                timestamp: row.timestamp ?? Date(),
                contentHash: contentHash,
                typeRawValue: row.contentType.rawValue,
                plainText: storedText.inlineText,
                fullTextData: storedText.fullTextData,
                isPlainTextTruncated: storedText.isTruncated,
                appBundleID: source.migratedBundleIdentifier,
                appLocalizedName: resolvedAppName(for: row, source: source),
                groupId: targetGroup.id,
                groupIdsRaw: Self.encodedGroupIDs([targetGroup.id]),
                sourcePlatformRawValue: ClipboardSourceMetadata.currentPlatform,
                sourceDeviceName: nil,
                captureMethodRawValue: ClipboardSourceMetadata.importedMethod
            )
            context.insert(record)
            recordsByHash[contentHash] = record
            importedCount += 1
            didMutateContext = true
        }

        if didMutateContext {
            try context.save()
            NotificationCenter.default.post(
                name: .didFinishDataMigration,
                object: source
            )
        }

        return MigrationReport(
            importedCount: importedCount,
            skippedCount: skippedCount,
            didMutateStore: didMutateContext
        )
    }
}
