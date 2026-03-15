import Foundation
import SwiftData

struct ClipboardRuntime {
    let syncEnabled: Bool
    let container: ModelContainer
    let storage: StorageManager
}

enum ClipboardContainerFactoryError: LocalizedError {
    case cloudStoreResetFailed(initialError: Error, resetError: Error)
    case cloudStoreRecoveryFailed(initialError: Error, retryError: Error)

    var errorDescription: String? {
        switch self {
        case let .cloudStoreResetFailed(initialError, resetError):
            return "iCloud 本地缓存重置失败。初始错误：\(initialError.localizedDescription)；重置错误：\(resetError.localizedDescription)"
        case let .cloudStoreRecoveryFailed(initialError, retryError):
            return "iCloud 本地缓存已重建，但云容器仍无法启动。初始错误：\(initialError.localizedDescription)；重试错误：\(retryError.localizedDescription)"
        }
    }
}

final class ClipboardModelContainerFactory: @unchecked Sendable {
    static let shared = ClipboardModelContainerFactory()
    static let cloudKitContainerIdentifier = "iCloud.com.gangz1o.clipaste"

    private init() {}

    func makeRuntime(syncEnabled: Bool) throws -> ClipboardRuntime {
        do {
            return try buildRuntime(syncEnabled: syncEnabled)
        } catch {
            guard syncEnabled else { throw error }

            let initialError = error

            do {
                try Self.resetStoreArtifacts(at: Self.cloudStoreURL)
            } catch {
                throw ClipboardContainerFactoryError.cloudStoreResetFailed(
                    initialError: initialError,
                    resetError: error
                )
            }

            do {
                return try buildRuntime(syncEnabled: syncEnabled)
            } catch {
                throw ClipboardContainerFactoryError.cloudStoreRecoveryFailed(
                    initialError: initialError,
                    retryError: error
                )
            }
        }
    }

    func makeContainer(syncEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([ClipboardRecord.self, ClipboardGroupModel.self])
        let configuration = ModelConfiguration(
            syncEnabled ? "ClipboardCloudStore" : "ClipboardLocalStore",
            schema: schema,
            url: syncEnabled ? Self.cloudStoreURL : Self.localStoreURL,
            cloudKitDatabase: syncEnabled ? .automatic : .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func buildRuntime(syncEnabled: Bool) throws -> ClipboardRuntime {
        let container = try makeContainer(syncEnabled: syncEnabled)
        let storage = StorageManager(modelContainer: container)
        return ClipboardRuntime(syncEnabled: syncEnabled, container: container, storage: storage)
    }

    private static var applicationSupportDirectory: URL {
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

    private static var storesDirectory: URL {
        let directory = applicationSupportDirectory.appendingPathComponent("Stores", isDirectory: true)

        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    static var localStoreURL: URL {
        storesDirectory.appendingPathComponent("clipboard-local.store", isDirectory: false)
    }

    static var cloudStoreURL: URL {
        storesDirectory.appendingPathComponent("clipboard-cloud.store", isDirectory: false)
    }

    private static func resetStoreArtifacts(at storeURL: URL) throws {
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
