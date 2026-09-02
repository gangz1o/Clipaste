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
        let startupBootstrap = try source(root, "clipaste/Managers/ClipboardRuntimeStore+Bootstrap.swift")
        let cloudAvailability = try source(root, "clipaste/Managers/CloudSyncAvailabilityService.swift")
        let panelRoot = try source(root, "clipaste/Managers/ClipboardPanelRootView.swift")
        let panelPresentation = try source(root, "clipaste/Managers/ClipboardPanelManager+Presentation.swift")
        let card = try source(root, "clipaste/Views/ClipboardCardView.swift")
        let cardContent = try source(root, "clipaste/Views/ClipboardCardView+Content.swift")
        let viewModel = try source(root, "clipaste/ViewModels/ClipboardViewModel.swift")
        let historyLoading = try source(root, "clipaste/ViewModels/ClipboardViewModel+HistoryLoading.swift")
        let quickPasteRouting = try source(root, "clipaste/ViewModels/ClipboardViewModel+QuickPaste.swift")
        let filtering = try source(root, "clipaste/ViewModels/ClipboardViewModel+Filtering.swift")
        let filterEngine = try source(root, "clipaste/Services/ClipboardFilterEngine.swift")
        let quickPasteVisibility = try source(root, "clipaste/Views/ClipboardQuickPasteVisibility.swift")
        let quickPasteViews = try source(root, "clipaste/Views/QuickPasteShortcutView.swift")
        let horizontalList = try source(root, "clipaste/Views/ClipboardHorizontalView.swift")
        let verticalItem = try source(root, "clipaste/Views/ClipboardVerticalItemView.swift")
        let verticalItemContent = try source(root, "clipaste/Views/ClipboardVerticalItemView+Content.swift")
        let verticalList = try source(root, "clipaste/Views/ClipboardVerticalListView.swift")
        let itemPreview = try source(root, "clipaste/Views/ClipboardItemPreviewView.swift")
        let mainView = try source(root, "clipaste/Views/ClipboardMainView.swift")
        let mainViewFocus = try source(root, "clipaste/Views/ClipboardMainView+Focus.swift")
        let historyView = try source(root, "clipaste/Views/ClipboardHistoryView.swift")

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
        precondition(startupBootstrap.contains("CloudSyncAvailabilityService.accountRecordName") == false)
        precondition(cloudAvailability.contains("nonisolated enum CloudSyncAvailabilityService"))
        precondition(cloudAvailability.components(separatedBy: "@concurrent").count == 3)

        precondition(card.contains("loadAppIconDominantColorHex") == false)
        precondition(card.contains("dominantColorHex()") == false)
        precondition(card.contains("item.appIconDominantColorHex"))
        precondition(viewModel.contains("@Observable"))
        precondition(viewModel.contains("@AppStorage") == false)
        precondition(filtering.contains("DispatchQueue.global") == false)
        precondition(filterEngine.contains("ClipboardFilterSnapshot: Sendable"))
        precondition(filterEngine.contains("Task.isCancelled"))
        precondition(filterEngine.contains("case cancelled"))
        precondition(quickPasteVisibility.contains("if isEnabled"))
        precondition(horizontalList.contains("isEnabled: viewModel.isQuickPasteModifierHeld"))
        precondition(verticalList.contains("isEnabled: viewModel.isQuickPasteModifierHeld"))
        precondition(quickPasteViews.contains("keyboardShortcut") == false)
        precondition(card.contains("QuickPasteShortcutHost") == false)
        precondition(verticalItemContent.contains("QuickPasteShortcutHost") == false)
        precondition(quickPasteRouting.contains("handleQuickPasteShortcut"))
        precondition(quickPasteRouting.contains("quickPasteTargetsByNumber"))
        precondition(horizontalList.contains("loadMoreHistoryIfNeeded"))
        precondition(verticalList.contains("loadMoreHistoryIfNeeded"))
        precondition(historyLoading.contains("while !Task.isCancelled") == false)
        precondition(historyLoading.contains("loadMoreHistoryIfNeeded"))
        precondition(panelPresentation.contains("setFrame(hiddenFrame, display: false)"))
        precondition(panelPresentation.range(of: "isVisible = true")!.lowerBound
            < panelPresentation.range(of: "panel.makeKeyAndOrderFront")!.lowerBound)
        precondition(mainView.contains("onChange(of: displayedItemIDs)") == false)
        precondition(mainViewFocus.contains("applyPendingListFocusWhenReady"))
        precondition(mainView.contains("@State var viewModel = ClipboardViewModel()") == false)
        precondition(historyView.contains("@State private var viewModel = ClipboardViewModel()") == false)
        precondition(panelRoot.contains("@State private var viewModel = ClipboardViewModel()"))
        precondition(panelRoot.contains("ClipboardMainView(viewModel: viewModel)"))
        precondition(historyLoading.contains("isLoadingMoreHistory = pageItems.count") == false)
        precondition(quickPasteRouting.contains("plainTextModifiers != quickPasteModifiers"))
        precondition(card.contains("headerTimestampText") == false)
        precondition(cardContent.contains("timestamp.dateString") == false)
        precondition(verticalItem.contains("timestamp.timeString") == false)
        precondition(verticalItemContent.contains("timestamp.timeString") == false)
        precondition(itemPreview.contains("timestamp.timeString") == false)

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
