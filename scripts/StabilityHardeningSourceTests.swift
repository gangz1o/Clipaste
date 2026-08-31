import Foundation

@main
enum StabilityHardeningSourceTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let monitor = try moduleSources(root, directory: "clipaste/Managers", prefixes: ["ClipboardMonitor"])
        let containerFactory = try source(root, "clipaste/Managers/ClipboardModelContainerFactory.swift")
        let runtime = try moduleSources(root, directory: "clipaste/Managers", prefixes: ["ClipboardRuntimeStore"])
        let storage = try moduleSources(
            root,
            directory: "clipaste/Managers",
            prefixes: ["StorageManager", "ClipboardStoreActor"]
        )
        let bootstrapper = try source(root, "clipaste/Managers/ClipboardStoreBootstrapper.swift")
        let card = try source(root, "clipaste/Views/ClipboardCardView.swift")
        let viewModel = try source(root, "clipaste/ViewModels/ClipboardViewModel.swift")
        let filtering = try source(root, "clipaste/ViewModels/ClipboardViewModel+Filtering.swift")
        let filterEngine = try source(root, "clipaste/Services/ClipboardFilterEngine.swift")
        let verticalList = try source(root, "clipaste/Views/ClipboardVerticalListView.swift")

        precondition(monitor.contains("let storage = StorageManager.shared"))
        precondition(monitor.contains("stopMonitoringAndDrain"))
        precondition(containerFactory.contains("cloudStoreResetFailed") == false)
        precondition(runtime.contains("ClipboardStorageTransitionBarrier.quiesce"))
        precondition(runtime.contains("sourceStorage: sourceRuntime.storage"))
        precondition(runtime.contains("await retiringCloudRuntime.storage.shutdown()"))
        precondition(runtime.range(of: "shutdown()")!.lowerBound < runtime.range(of: "resetCloudStoreArtifacts()")!.lowerBound)
        precondition(runtime.contains("defaults.set(resolvedSyncEnabled, forKey: Keys.syncEnabled)"))
        precondition(runtime.contains("exportRecordBatch"))
        precondition(storage.contains("descriptor.fetchLimit = pageSize"))
        precondition(storage.contains("let records = try modelContext.fetch(descriptor)\n            counts.reserveCapacity") == false)
        precondition(storage.contains("try export.validatedPayloadByteCount()"))
        precondition(bootstrapper.contains("try export.validatedPayloadByteCount()"))
        precondition(bootstrapper.contains("min(\n                        export.estimatedPayloadByteCount") == false)

        precondition(card.contains("loadAppIconDominantColorHex") == false)
        precondition(card.contains("dominantColorHex()") == false)
        precondition(card.contains("item.appIconDominantColorHex"))
        precondition(viewModel.contains("@Observable"))
        precondition(viewModel.contains("@AppStorage") == false)
        precondition(filtering.contains("DispatchQueue.global") == false)
        precondition(filterEngine.contains("ClipboardFilterSnapshot: Sendable"))
        precondition(filterEngine.contains("Task.isCancelled"))
        precondition(filterEngine.contains("case cancelled"))

        let scrollFunction = verticalList.components(separatedBy: "private func scrollToItem").last ?? ""
        precondition(scrollFunction.contains("DispatchQueue.main.async") == false)
        print("StabilityHardeningSourceTests passed")
    }

    private static func source(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func moduleSources(
        _ root: URL,
        directory: String,
        prefixes: [String]
    ) throws -> String {
        let directoryURL = root.appendingPathComponent(directory, isDirectory: true)
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return try fileURLs
            .filter { url in
                url.pathExtension == "swift"
                    && prefixes.contains { url.lastPathComponent.hasPrefix($0) }
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
