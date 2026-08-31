import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - String Utilities

extension MigrationManager {
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
