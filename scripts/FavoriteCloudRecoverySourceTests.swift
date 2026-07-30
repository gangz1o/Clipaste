import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum FavoriteCloudRecoverySourceTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: FavoriteCloudRecoverySourceTests <repository-root>\n", stderr)
            exit(2)
        }

        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let storageSource = try String(
            contentsOf: rootURL.appending(path: "clipaste/Managers/StorageManager.swift"),
            encoding: .utf8
        )
        let runtimeSource = try String(
            contentsOf: rootURL.appending(path: "clipaste/Managers/ClipboardRuntimeStore.swift"),
            encoding: .utf8
        )

        expect(
            storageSource.contains("func exportPinnedRecords() async throws -> ClipboardStoreExport"),
            "storage facade must expose a throwing pinned-only export"
        )
        expect(
            storageSource.contains("#Predicate<ClipboardRecord> { $0.isPinned }"),
            "pinned recovery must filter in SwiftData instead of exporting all history"
        )
        expect(
            storageSource.contains("referencedGroupIDs"),
            "pinned recovery must retain referenced group definitions"
        )
        expect(
            runtimeSource.contains("recoverLocalFavoritesIfNeeded"),
            "cloud startup must invoke the local favorite recovery"
        )
        expect(
            runtimeSource.contains("favoriteRecoveryVersion"),
            "favorite recovery must have a versioned completion marker"
        )

        guard let recoveryStart = runtimeSource.range(of: "private func recoverLocalFavoritesIfNeeded() async throws"),
              let recoveryEnd = runtimeSource.range(
                of: "private func repairDuplicateRecordsIfThrottled",
                range: recoveryStart.upperBound..<runtimeSource.endIndex
              ) else {
            fputs("FAIL: favorite recovery implementation body must exist\n", stderr)
            exit(1)
        }
        let recoverySource = String(runtimeSource[recoveryStart.lowerBound..<recoveryEnd.lowerBound])

        guard let importRange = recoverySource.range(of: "importStoreExport(payload)"),
              let markerRange = recoverySource.range(
                of: "defaults.set(FavoriteRecovery.currentVersion, forKey: Keys.favoriteRecoveryVersion)"
              ) else {
            fputs("FAIL: recovery import and success marker must both exist\n", stderr)
            exit(1)
        }
        expect(
            importRange.lowerBound < markerRange.lowerBound,
            "completion marker must be written only after the cloud-store import succeeds"
        )

        print("FavoriteCloudRecoverySourceTests passed")
    }
}
