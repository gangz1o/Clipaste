import Foundation
import SwiftData

private struct ClipboardRecordSnapshot: Sendable {
    let id: UUID
    let contentHash: String
    let bundleIdentifier: String?
    let appName: String
    let timestamp: Date
    let plainText: String?
    let thumbnailPath: String?
    let typeRawValue: String
}

@ModelActor
actor ClipboardSearcher {
    func searchAndMap(searchText: String) async -> [ClipboardItem] {
        let query = searchText
        let descriptor: FetchDescriptor<ClipboardRecord>

        if query.isEmpty {
            descriptor = FetchDescriptor<ClipboardRecord>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            let predicate = #Predicate<ClipboardRecord> { record in
                (record.plainText?.localizedStandardContains(query) == true) ||
                (record.appLocalizedName?.localizedStandardContains(query) == true)
            }

            descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = records.map { record in
            ClipboardRecordSnapshot(
                id: record.id,
                contentHash: record.contentHash,
                bundleIdentifier: record.appBundleID,
                appName: record.appLocalizedName ?? "Unknown App",
                timestamp: record.timestamp,
                plainText: record.plainText,
                thumbnailPath: record.thumbnailPath,
                typeRawValue: record.typeRawValue
            )
        }

        return await MainActor.run {
            snapshots.map(StorageManager.makeClipboardItem(from:))
        }
    }
}

final class StorageManager {
    nonisolated static let shared = StorageManager()
    nonisolated let container: ModelContainer

    private init() {
        do {
            self.container = try ModelContainer(for: ClipboardRecord.self)
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    nonisolated
    func fetchItemsInBackground(searchText: String, container: ModelContainer) async -> [ClipboardItem] {
        let searcher = ClipboardSearcher(modelContainer: container)
        return await searcher.searchAndMap(searchText: searchText)
    }

    @MainActor
    func fetchRecord(id: UUID) -> ClipboardRecord? {
        let context = container.mainContext
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.id == id
            }
        )
        descriptor.fetchLimit = 1

        return try? context.fetch(descriptor).first
    }

    nonisolated
    func recordExists(hash: String) -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate<ClipboardRecord> { record in
                record.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first != nil
        } catch {
            return false
        }
    }

    nonisolated
    func upsertRecord(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        type: String,
        thumbnailPath: String?,
        originalFilePath: String?
    ) {
        let container = self.container

        // Keep disk I/O off the caller's thread, but do not drop QoS so low that
        // SwiftData store locking creates a priority inversion with UI/search reads.
        Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            let descriptor = FetchDescriptor<ClipboardRecord>(
                predicate: #Predicate<ClipboardRecord> { record in
                    record.contentHash == hash
                }
            )
            let now = Date()

            do {
                if let existingRecord = try backgroundContext.fetch(descriptor).first {
                    existingRecord.timestamp = now
                    existingRecord.typeRawValue = type
                    existingRecord.plainText = text
                    if let thumbnailPath {
                        existingRecord.thumbnailPath = thumbnailPath
                    }
                    if let originalFilePath {
                        existingRecord.originalFilePath = originalFilePath
                    }
                    existingRecord.appBundleID = appID
                    existingRecord.appLocalizedName = appName
                } else {
                    let newRecord = ClipboardRecord(
                        timestamp: now,
                        contentHash: hash,
                        typeRawValue: type,
                        plainText: text,
                        thumbnailPath: thumbnailPath,
                        originalFilePath: originalFilePath,
                        appBundleID: appID,
                        appLocalizedName: appName
                    )
                    backgroundContext.insert(newRecord)
                }

                try backgroundContext.save()
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            } catch {
                print("Background save failed: \(error)")
            }
        }
    }

    @MainActor
    fileprivate static func makeClipboardItem(from record: ClipboardRecordSnapshot) -> ClipboardItem {
        let id = record.id
        let contentHash = record.contentHash
        let bundleIdentifier = record.bundleIdentifier
        let appName = record.appName
        let timestamp = record.timestamp
        let plainText = record.plainText
        let thumbnailPath = record.thumbnailPath
        let type = ClipboardContentType(rawValue: record.typeRawValue) ?? .text
        let appIcon = bundleIdentifier.flatMap { AppIconManager.shared.getIcon(for: $0) }

        return ClipboardItem(
            id: id,
            contentType: type,
            contentHash: contentHash,
            textPreview: makeTextPreview(plainText: plainText, type: type),
            sourceBundleIdentifier: bundleIdentifier,
            appName: appName,
            appIcon: appIcon,
            appIconName: ClipboardItem.appIconName(for: bundleIdentifier),
            timestamp: timestamp,
            rawText: type == .text ? plainText : nil,
            imagePath: type == .image ? thumbnailPath : nil,
            thumbnailURL: type == .image ? LocalFileManager.shared.url(forRelativePath: thumbnailPath) : nil,
            fileURL: type == .fileURL ? plainText : nil
        )
    }

    fileprivate static func makeTextPreview(plainText: String?, type: ClipboardContentType) -> String {
        switch type {
        case .text:
            return plainText ?? ""
        case .fileURL:
            guard
                let plainText,
                let url = URL(string: plainText),
                url.isFileURL,
                !url.lastPathComponent.isEmpty
            else {
                return plainText ?? "File"
            }

            return url.lastPathComponent
        case .image:
            return "Image"
        case .color:
            return plainText ?? "Color"
        }
    }
}
