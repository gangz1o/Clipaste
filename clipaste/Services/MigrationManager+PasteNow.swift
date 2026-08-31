import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - PasteNow JSON Engine (Preserved)

extension MigrationManager {
    nonisolated static func loadPasteNowJSONRows(from fileURL: URL) async throws -> [MigratedClipboardRow] {
        try await Task.detached(priority: .userInitiated) {
            try readJSONRows(
                from: fileURL,
                configuration: JSONExtractorConfiguration(
                    collectionKeys: ["items", "clips", "history", "histories", "records", "data", "clipboard", "list"],
                    textKeys: ["text", "content", "value", "cliptext", "plaintext", "memo"],
                    dateKeys: ["timestamp"],
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
            .compactMap(decodeUnixTimestamp(_:))
            .first
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
            timestamp: timestamp,
            sourceAppName: sourceAppName,
            groupName: groupName,
            contentType: inferContentType(from: text)
        )
    }
}
