import CloudKit
import CoreData
import Foundation
import os
import SwiftData

struct CloudKitServerDiagnosticsSnapshot: Sendable {
    let recordCount: Int
    let groupCount: Int
}

enum CloudKitServerDiagnosticsService {
    private static let clipboardRecordType = "CD_ClipboardRecord"
    private static let clipboardGroupType = "CD_ClipboardGroupModel"

    static func snapshot(containerIdentifier: String) async throws -> CloudKitServerDiagnosticsSnapshot {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let counts = try await countRecords(database: database)

        return CloudKitServerDiagnosticsSnapshot(
            recordCount: counts.records,
            groupCount: counts.groups
        )
    }

    private static func countRecords(database: CKDatabase) async throws -> (records: Int, groups: Int) {
        let zoneIDs = try await fetchRecordZoneIDs(database: database)
        var recordCount = 0
        var groupCount = 0

        for zoneID in zoneIDs {
            let zoneCounts = try await countRecords(in: zoneID, database: database)
            recordCount += zoneCounts.records
            groupCount += zoneCounts.groups
        }

        return (recordCount, groupCount)
    }

    private static func countRecords(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> (records: Int, groups: Int) {
        if zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
            do {
                let records = try await countQueryRecords(ofType: clipboardRecordType, in: zoneID, database: database)
                let groups = try await countQueryRecords(ofType: clipboardGroupType, in: zoneID, database: database)
                return (records, groups)
            } catch {
                return (0, 0)
            }
        }

        return try await countChangedRecords(in: zoneID, database: database)
    }

    private static func countQueryRecords(
        ofType recordType: String,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let firstPage = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: [],
            resultsLimit: 200
        )
        var count = successfulRecordCount(firstPage.matchResults)
        var cursor = firstPage.queryCursor

        while let currentCursor = cursor {
            let page = try await database.records(
                continuingMatchFrom: currentCursor,
                desiredKeys: [],
                resultsLimit: 200
            )
            count += successfulRecordCount(page.matchResults)
            cursor = page.queryCursor
        }

        return count
    }

    private static func countChangedRecords(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> (records: Int, groups: Int) {
        var recordCount = 0
        var groupCount = 0
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                desiredKeys: [],
                resultsLimit: nil
            )

            for result in changes.modificationResultsByID.values {
                guard case let .success(modification) = result else { continue }
                switch modification.record.recordType {
                case clipboardRecordType:
                    recordCount += 1
                case clipboardGroupType:
                    groupCount += 1
                default:
                    break
                }
            }

            changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        return (recordCount, groupCount)
    }

    private static func successfulRecordCount(
        _ results: [(CKRecord.ID, Result<CKRecord, Error>)]
    ) -> Int {
        results.reduce(0) { count, result in
            guard case .success = result.1 else { return count }
            return count + 1
        }
    }

    private static func fetchRecordZoneIDs(database: CKDatabase) async throws -> [CKRecordZone.ID] {
        var zoneIDs: Set<CKRecordZone.ID> = [CKRecordZone.default().zoneID]
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let changes = try await database.databaseChanges(since: changeToken, resultsLimit: nil)
            for modification in changes.modifications {
                zoneIDs.insert(modification.zoneID)
            }
            changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        return Array(zoneIDs)
    }
}
