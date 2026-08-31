import AppKit
import SwiftUI

extension ClipboardViewModel {
    func aiConfiguration(for skill: AISkill) -> AIConfiguration? {
        if let configurationID = skill.configurationID {
            return aiSettingsViewModel.configurations.first { $0.id == configurationID }
        }

        return aiSettingsViewModel.activeConfiguration
    }

    func applyAIResult(_ result: String, mode: AISkillOutputMode, item: ClipboardItem? = nil) {
        switch mode {
        case .copyToClipboard:
            PasteEngine.shared.writePlainTextToPasteboard(text: result)
            playCopySound()
            showOperationNotice(String(localized: "AI result copied to clipboard."))
        case .openConversation:
            showOperationNotice(String(localized: "AI conversation opened."))
        case .createClipboardItem:
            createClipboardItemFromAIResult(result)
            showOperationNotice(String(localized: "AI result added to clipboard history."))
        case .replaceCurrentItem:
            guard let item else {
                showOperationNotice(String(localized: "No clipboard item is available to replace."))
                return
            }
            saveEditedItem(item, newText: result)
            ListRenderEngine.shared.invalidate(id: item.id)
            showOperationNotice(String(localized: "AI result replaced the current item."))
        case .pasteToActiveApp:
            PasteEngine.shared.writePlainTextToPasteboard(text: result)
            ClipboardPanelManager.shared.forceHidePanel()
            Task { @MainActor in
                try? await Task.sleep(for: PasteEngine.postHidePasteDelay)
                PasteEngine.shared.simulateCommandV()
            }
        }
    }

    func createClipboardItemFromAIResult(_ result: String) {
        let data = Data(result.utf8)
        let hash = CryptoHelper.sha256(data: data)
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let appIconData = bundleIdentifier.flatMap { AppIconManager.shared.iconPNGData(for: $0) }
        let appIconDominantColorHex = appIconData.flatMap { NSImage(data: $0)?.dominantColorHex() }
        let sourcePlatformRawValue = ClipboardSourceMetadata.currentPlatform
        let sourceDeviceName = ClipboardSourceMetadata.currentDeviceName
        let generatedMethod = ClipboardSourceMetadata.generatedMethod

        StorageManager.shared.upsertRecord(
            hash: hash,
            text: result,
            appID: bundleIdentifier,
            appName: "Clipaste AI",
            appIconDominantColorHex: appIconDominantColorHex,
            appIconData: appIconData,
            type: ClipboardContentType.text.rawValue,
            sourcePlatformRawValue: sourcePlatformRawValue,
            sourceDeviceName: sourceDeviceName,
            captureMethodRawValue: generatedMethod
        )
    }

    var operationNoticeLocale: Locale {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
        return language.resolvedLocale
    }

    func showFavoritesDeletionBlockedNotice() {
        showOperationNotice(
            String(
                localized: "Items in Favorites can't be deleted. Remove them from Favorites first.",
                locale: operationNoticeLocale
            )
        )
    }

    func showFavoritesPreservedNotice(deletedCount: Int, preservedCount: Int) {
        let format = String(
            localized: "Deleted %lld items. Kept %lld item(s) in Favorites.",
            locale: operationNoticeLocale
        )
        let message = withVaList([deletedCount, preservedCount]) { pointer in
            NSString(format: format, locale: operationNoticeLocale, arguments: pointer) as String
        }
        showOperationNotice(message)
    }

    func showOperationNotice(_ message: String) {
        operationNoticeHideTask?.cancel()
        operationNotice = message

        operationNoticeHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard Task.isCancelled == false else { return }
            self?.operationNotice = nil
            self?.operationNoticeHideTask = nil
        }
    }

    var selectedItemsForBatchAction: [ClipboardItem] {
        let ids = selectedItemIDs
        guard !ids.isEmpty else { return [] }
        return displayedItemsForInteraction.filter { ids.contains($0.id) }
    }

    func batchSetFavoriteState(_ isFavorite: Bool) {
        let targetItems = selectedItemsForBatchAction
        guard !targetItems.isEmpty else { return }

        for item in targetItems {
            setFavoriteState(for: item, isFavorite: isFavorite)
        }

        clearSelection()
    }

    func setFavoriteState(for item: ClipboardItem, isFavorite: Bool) {
        guard item.isPinned != isFavorite else { return }

        updateItem(id: item.id) { updatedItem in
            updatedItem.isPinned = isFavorite
        }

        StorageManager.shared.togglePin(hash: item.contentHash, isPinned: isFavorite)
    }
}
