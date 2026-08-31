import CloudKit
import CoreData
import Foundation
import os
import SwiftData

private final class ClipboardStorageBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var currentStorage: StorageManager?

    nonisolated func update(storage: StorageManager) {
        lock.lock()
        currentStorage = storage
        lock.unlock()
    }

    nonisolated func storage() -> StorageManager {
        lock.lock()
        if let currentStorage {
            lock.unlock()
            return currentStorage
        }
        lock.unlock()

        let recoveryStorage: StorageManager
        do {
            recoveryStorage = try ClipboardModelContainerFactory.shared.makeInMemoryRuntime().storage
        } catch {
            preconditionFailure("Unable to initialize emergency clipboard storage: \(error)")
        }

        lock.lock()
        defer { lock.unlock() }
        if let currentStorage {
            return currentStorage
        }
        currentStorage = recoveryStorage
        return recoveryStorage
    }
}

enum ClipboardStorageRegistry {
    nonisolated private static let box = ClipboardStorageBox()

    nonisolated static func update(storage: StorageManager) {
        box.update(storage: storage)
    }

    nonisolated static func storage() -> StorageManager {
        box.storage()
    }
}
