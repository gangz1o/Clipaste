import Foundation
import SwiftData

// Minimal collaborators for compiling the production record, transfer and maintenance code.
enum ClipboardContentType: String, Codable, Sendable {
    case text, image, fileURL, color, link, code
}

enum TextSyncSizeLimit: String {
    case unlimited
    static let defaultsKey = "text_sync_size_limit"
    var limitBytes: Int? { nil }
}

struct ClipboardRichTextArchive {
    static func fromRTFData(_ data: Data) -> ClipboardRichTextArchive? { nil }
    func encodedData() -> Data? { nil }
}

enum IconType {
    case system, custom
}

@MainActor
enum IconPickerViewModel {
    static let customIconNames: Set<String> = []
}

@ModelActor
actor ClipboardStoreActor {
    /// 时间戳每 3 条相同,覆盖"时间相同按 id 排序"。
    func seed(count: Int, hash: (Int) -> String = { "r\($0)" }, imageBytes: Int = 0) throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<count {
            let isPinned = index.isMultiple(of: 10)
            modelContext.insert(ClipboardRecord(
                timestamp: base.addingTimeInterval(TimeInterval(index / 3)),
                contentHash: hash(index),
                typeRawValue: imageBytes > 0 ? "image" : "text",
                plainText: "item \(index)",
                imageData: imageBytes > 0 ? Data(count: imageBytes) : nil,
                groupId: isPinned ? "pinned-group" : nil,
                isPinned: isPinned,
                topPinOrder: index == 0 ? 1234 : 0
            ))
        }
        modelContext.insert(ClipboardGroupModel(id: "pinned-group", name: "Pinned"))
        modelContext.insert(ClipboardGroupModel(id: "unused-group", name: "Unused"))
        try modelContext.save()
    }

    /// 旧实现的导出顺序:排序后的全部 contentHash。
    func expectedHashes(pinnedOnly: Bool) throws -> [String] {
        let descriptor = FetchDescriptor<ClipboardRecord>(
            predicate: pinnedOnly ? #Predicate<ClipboardRecord> { $0.isPinned } : nil,
            sortBy: Self.exportSortOrder
        )
        return try modelContext.fetch(descriptor).map(\.contentHash)
    }

    func deleteRecords(hashes: Set<String>) throws {
        for record in try modelContext.fetch(FetchDescriptor<ClipboardRecord>()) where hashes.contains(record.contentHash) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    func storedHashes() throws -> [String] {
        try modelContext.fetch(FetchDescriptor<ClipboardRecord>()).map(\.contentHash)
    }
}

func makeTemporaryContainer() throws -> ModelContainer {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipaste-transfer-\(UUID().uuidString)")
        .appendingPathComponent("test.store")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return try ModelContainer(
        for: ClipboardRecord.self, ClipboardGroupModel.self, SyncAnchor.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
}

func drain(_ cursor: ClipboardRecordExportCursor, limit: Int) async throws -> [ClipboardStoreExport] {
    var batches: [ClipboardStoreExport] = []
    while true {
        let batch = try await cursor.nextBatch(limit: limit)
        guard batch.records.isEmpty == false else { return batches }
        precondition(batch.records.count <= limit)
        batches.append(batch)
    }
}
