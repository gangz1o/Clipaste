import Foundation
import SwiftData

struct ClipboardRuntime: @unchecked Sendable {
    let syncEnabled: Bool
    let container: ModelContainer
    let storage: StorageManager
}

final class ClipboardModelContainerFactory: @unchecked Sendable {
    nonisolated static let shared = ClipboardModelContainerFactory()
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.gangz1o.clipaste"
    #if DEBUG
    nonisolated static let cloudKitEnvironmentName = "Development"
    #else
    nonisolated static let cloudKitEnvironmentName = "Production"
    #endif

    private nonisolated init() {}

    nonisolated func makeRuntime(syncEnabled: Bool) throws -> ClipboardRuntime {
        try buildRuntime(syncEnabled: syncEnabled)
    }

    nonisolated func makeContainer(syncEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([ClipboardRecord.self, ClipboardGroupModel.self, SyncAnchor.self])
        let configuration = ModelConfiguration(
            syncEnabled ? "ClipboardCloudStore" : "ClipboardLocalStore",
            schema: schema,
            url: syncEnabled ? Self.cloudStoreURL : Self.localStoreURL,
            cloudKitDatabase: syncEnabled ? .private(Self.cloudKitContainerIdentifier) : .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    nonisolated func makeInMemoryRuntime() throws -> ClipboardRuntime {
        let schema = Schema([ClipboardRecord.self, ClipboardGroupModel.self, SyncAnchor.self])
        let configuration = ModelConfiguration(
            "ClipboardRecoveryStore",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let storage = StorageManager(modelContainer: container)
        return ClipboardRuntime(syncEnabled: false, container: container, storage: storage)
    }

    private nonisolated func buildRuntime(syncEnabled: Bool) throws -> ClipboardRuntime {
        let container = try makeContainer(syncEnabled: syncEnabled)
        let storage = StorageManager(modelContainer: container)
        return ClipboardRuntime(syncEnabled: syncEnabled, container: container, storage: storage)
    }

    private nonisolated static var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "clipaste"
        let directory = baseDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) == false {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private nonisolated static var storesDirectory: URL {
        let directory = applicationSupportDirectory.appendingPathComponent("Stores", isDirectory: true)

        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    nonisolated static var localStoreURL: URL {
        storesDirectory.appendingPathComponent("clipboard-local.store", isDirectory: false)
    }

    nonisolated static var cloudStoreURL: URL {
        storesDirectory.appendingPathComponent("clipboard-cloud.store", isDirectory: false)
    }

    nonisolated static func resetCloudStoreArtifacts() throws {
        try resetStoreArtifacts(at: cloudStoreURL)
    }

    private nonisolated static func resetStoreArtifacts(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = storeURL.deletingLastPathComponent()
        let storePrefix = storeURL.lastPathComponent

        guard fileManager.fileExists(atPath: directoryURL.path) else { return }

        let candidateURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for candidateURL in candidateURLs where candidateURL.lastPathComponent.hasPrefix(storePrefix) {
            try fileManager.removeItem(at: candidateURL)
        }
    }
}
