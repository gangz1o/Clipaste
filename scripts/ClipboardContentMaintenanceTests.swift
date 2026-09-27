import Foundation
import SwiftData

@main
enum ClipboardContentMaintenanceTests {
    static func main() async throws {
        let container = try ModelContainer(
            for: ClipboardRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let actor = ClipboardStoreActor(modelContainer: container)
        try await actor.seed()

        let reclassified = await actor.repairTextClassificationsIfNeeded()
        let codeCount = try await actor.typeCount("code")
        let imageCount = try await actor.typeCount("image")
        let reclassifiedAgain = await actor.repairTextClassificationsIfNeeded()
        precondition(reclassified == 50, "Every third text record should become code, got \(reclassified)")
        precondition(codeCount == 50)
        precondition(imageCount == 1, "Non-text records must not be reclassified")
        precondition(reclassifiedAgain == 0, "Repair must be idempotent")

        let colorBundleIDs = await actor.fetchDistinctAppBundleIDsForColorRepair()
        let missingIconBundleIDs = await actor.fetchDistinctAppBundleIDsMissingIconData()
        precondition(colorBundleIDs.sorted() == ["com.a", "com.b", "migrated.app"])
        precondition(missingIconBundleIDs.sorted() == ["com.a", "migrated.app"])

        let recolored = await actor.repairAppIconDominantColors(using: ["com.a": "#FF0000"])
        let redCount = try await actor.colorCount("#FF0000")
        let recoloredAgain = await actor.repairAppIconDominantColors(using: ["com.a": "#FF0000"])
        precondition(recolored == 76, "Expected 76 com.a records, got \(recolored)")
        precondition(redCount == 76, "Only com.a records get the repaired color")
        precondition(recoloredAgain == 0)

        let iconRepaired = await actor.repairAppIconData(using: ["com.a": Data([9])])
        let stillMissing = await actor.fetchDistinctAppBundleIDsMissingIconData()
        precondition(iconRepaired == 76)
        precondition(stillMissing == ["migrated.app"])

        let timestampRepaired = await actor.repairImportedMigrationTimestampsIfNeeded()
        let migratedTimestamp = try await actor.timestamp(hash: "migrated")
        let nativeTimestamp = try await actor.timestamp(hash: "old-native")
        precondition(timestampRepaired == 1)
        precondition(migratedTimestamp.map { $0 > Date(timeIntervalSince1970: 0) } == true)
        precondition(nativeTimestamp == Date(timeIntervalSinceReferenceDate: -978_000_000),
                     "Only migrated sources get timestamp repairs")
        print("ClipboardContentMaintenanceTests passed")
    }
}
