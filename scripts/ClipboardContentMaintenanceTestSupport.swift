import Foundation
import SwiftData

// Minimal collaborators for compiling the production record and content maintenance.
enum ClipboardContentType: String {
    case text, code, link, image
}

enum ClipboardContentClassifier {
    static func classify(_ text: String) -> ClipboardContentType {
        text.contains("{") ? .code : .text
    }
}

enum MigrationManager {
    static let migratedBundleIdentifiers: Set<String> = ["migrated.app"]

    static func repairedDateIfLikelyMisdecodedReferenceTimestamp(_ date: Date, now: Date) -> Date? {
        date.addingTimeInterval(978_307_200)
    }
}

@ModelActor
actor ClipboardStoreActor {
    var textBasedTypes: Set<String> { ["text", "code", "link"] }

    func markSyncAnchorUpdated() throws { }

    /// 超过一个批次的记录,覆盖批内保存与跨批遍历。
    func seed() throws {
        for index in 0..<150 {
            let isCode = index.isMultiple(of: 3)
            modelContext.insert(ClipboardRecord(
                contentHash: "text-\(index)",
                typeRawValue: "text",
                plainText: isCode ? "func f() { \(index) }" : "plain \(index)",
                appBundleID: index.isMultiple(of: 2) ? "com.a" : " com.b ",
                appIconData: index.isMultiple(of: 2) ? nil : Data([1])
            ))
        }
        modelContext.insert(ClipboardRecord(contentHash: "image", typeRawValue: "image", plainText: "{ not text }"))
        modelContext.insert(ClipboardRecord(
            timestamp: Date(timeIntervalSinceReferenceDate: -978_000_000),
            contentHash: "migrated",
            typeRawValue: "text",
            appBundleID: "migrated.app"
        ))
        modelContext.insert(ClipboardRecord(
            timestamp: Date(timeIntervalSinceReferenceDate: -978_000_000),
            contentHash: "old-native",
            typeRawValue: "text",
            appBundleID: "com.a"
        ))
        try modelContext.save()
    }

    func records() throws -> [String: ClipboardRecord] {
        Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ClipboardRecord>()).map { ($0.contentHash, $0) })
    }

    func typeCount(_ type: String) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ClipboardRecord>(predicate: #Predicate { $0.typeRawValue == type }))
    }

    func colorCount(_ color: String) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ClipboardRecord>(
            predicate: #Predicate { $0.appIconDominantColorHex == color }
        ))
    }

    func timestamp(hash: String) throws -> Date? {
        try records()[hash]?.timestamp
    }
}
