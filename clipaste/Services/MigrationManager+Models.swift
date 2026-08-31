import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers


// MARK: - Internal Types

extension MigrationManager {
    struct MigrationReport {
        let importedCount: Int
        let skippedCount: Int
        let didMutateStore: Bool
    }

    nonisolated static let appleReferenceDateOffsetSince1970: TimeInterval = 978_307_200

    nonisolated static var migratedBundleIdentifiers: Set<String> {
        Set(MigrationSource.allCases.map(\.migratedBundleIdentifier))
    }

    nonisolated static func repairedDateIfLikelyMisdecodedReferenceTimestamp(
        _ date: Date,
        now: Date = Date()
    ) -> Date? {
        guard date < migrationTimestampLowerBound else {
            return nil
        }

        let correctedDate = date.addingTimeInterval(appleReferenceDateOffsetSince1970)
        guard migrationTimestampScore(for: correctedDate, now: now)
                < migrationTimestampScore(for: date, now: now) else {
            return nil
        }

        return correctedDate
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
            systemIconName: nil,
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
