import Foundation

@main
enum ClipboardFilterEngineTests {
    static func main() async {
        await testFilteringSemantics()
        await testCancellationIsObservable()
        print("ClipboardFilterEngineTests passed")
    }

    private static func testFilteringSemantics() async {
        let textID = UUID()
        let imageID = UUID()
        let snapshots = [
            ClipboardFilterSnapshot(
                id: textID,
                contentTypeRawValue: "text",
                groupIDs: ["work"],
                isPinned: true,
                searchableText: "Résumé Notes",
                appName: "Editor"
            ),
            ClipboardFilterSnapshot(
                id: imageID,
                contentTypeRawValue: "image",
                groupIDs: ["personal"],
                isPinned: false,
                searchableText: "Screenshot",
                appName: "Preview"
            )
        ]

        let result = await ClipboardFilterEngine.filteredIDs(
            snapshots: snapshots,
            query: "resume",
            groupID: "work",
            typeFilterRawValue: "text",
            favoritesOnly: true
        )
        precondition(result == .completed([textID]))
    }

    private static func testCancellationIsObservable() async {
        let longText = String(repeating: "a", count: 2_048)
        let snapshots = (0..<20_000).map { _ in
            ClipboardFilterSnapshot(
                id: UUID(),
                contentTypeRawValue: "text",
                groupIDs: [],
                isPinned: false,
                searchableText: longText,
                appName: "Editor"
            )
        }

        let task = Task {
            await ClipboardFilterEngine.filteredIDs(
                snapshots: snapshots,
                query: "not-present",
                groupID: nil,
                typeFilterRawValue: nil,
                favoritesOnly: false
            )
        }
        task.cancel()

        let result = await task.value
        precondition(result == .cancelled)
    }
}
