import Foundation
import SwiftData

extension StorageManager {
    nonisolated
    func clearUnpinnedHistory() {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.deleteUnpinnedRecords()
        }
    }

    nonisolated
    func createGroup(name: String, systemIconName: String? = nil) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.createGroup(name: name, systemIconName: systemIconName)
        }
    }

    nonisolated
    func assignToGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.assignRecordToGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromGroup(hash: String, groupId: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.removeRecordFromGroup(recordHash: hash, groupId: groupId)
        }
    }

    nonisolated
    func removeRecordFromAllGroups(hash: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.removeRecordFromAllGroups(recordHash: hash)
        }
    }

    nonisolated
    func renameGroup(id: String, newName: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupName(id: id, newName: newName)
        }
    }

    nonisolated
    func updateGroupIcon(id: String, newIcon: String?) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupIcon(id: id, newIcon: newIcon)
        }
    }

    nonisolated
    func deleteGroup(id: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.deleteGroup(id: id)
        }
    }

    nonisolated
    func updateGroupOrder(groupIDs: [String]) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateGroupOrder(groupIDs: groupIDs)
        }
    }

    func moveItemToTop(id: UUID) async {
        await storeActor.updateItemTimestampToNow(id: id)
    }

    nonisolated
    func updateRecordText(
        hash: String,
        newText: String,
        newRTFData: Data? = nil,
        newRichTextArchiveData: Data? = nil
    ) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateRecordText(
                hash: hash,
                newText: newText,
                newRTFData: newRTFData,
                newRichTextArchiveData: newRichTextArchiveData
            )
        }
    }

    nonisolated
    func updateRecordCustomTitle(hash: String, customTitle: String?) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updateRecordCustomTitle(hash: hash, customTitle: customTitle)
        }
    }
}
