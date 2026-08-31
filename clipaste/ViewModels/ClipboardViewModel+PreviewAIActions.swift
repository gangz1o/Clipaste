import AppKit
import SwiftUI

extension ClipboardViewModel {
    func showPreview(item: ClipboardItem) {
        if quickLookRequestedItemID == item.id || quickLookItem?.id == item.id {
            dismissQuickLook()
        } else {
            presentQuickLook(for: item)
        }
    }

    func shareItem(item: ClipboardItem) {
        sharingItem = item
    }

    func openLinkInDefaultBrowser(item: ClipboardItem) {
        guard let url = ClipboardLinkOpeningService.url(from: item) else {
            return
        }

        ClipboardLinkOpeningService.open(url)
    }

    func runAISkill(_ skill: AISkill, for item: ClipboardItem) {
        selectedItemIDs = [item.id]
        lastSelectedID = item.id
        aiSettingsViewModel.markSkillUsed(skill)

        guard let configuration = aiConfiguration(for: skill) else {
            showOperationNotice(String(localized: "No active AI configuration is available."))
            NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
            return
        }

        showOperationNotice(String(localized: "Running AI skill…"))

        Task { @MainActor in
            do {
                let prompt = try await AIExecutionService.shared.prompt(for: skill, item: item)
                let userMessage = AIChatMessage(role: "user", content: prompt)
                let result = try await AIExecutionService.shared.send(messages: [userMessage], configuration: configuration)
                let assistantMessage = AIChatMessage(role: "assistant", content: result)
                applyAIResult(result, mode: skill.outputMode, item: item)

                if skill.opensConversation || skill.outputMode == .openConversation {
                    AIConversationWindowManager.shared.openConversation(
                        title: skill.displayTitle,
                        configuration: configuration,
                        messages: [userMessage, assistantMessage]
                    )
                }
            } catch {
                showOperationNotice(error.localizedDescription)
            }
        }
    }

    func deleteItem(item: ClipboardItem) {
        guard item.isPinned == false else {
            showFavoritesDeletionBlockedNotice()
            print("🛡️ 已阻止删除收藏记录: \(item.id)")
            return
        }
        let fallbackSelectionID = selectionCandidateAfterRemoving(ids: [item.id])

        // Dismiss the QuickLook popover BEFORE the anchor card unmounts —
        // see batchDelete() for the rationale.
        if quickLookItem?.id == item.id {
            dismissQuickLook()
        }
        dismissAutoPreviewIfNeeded()

        withAnimation(.easeOut(duration: 0.2)) {
            removeItems(withIDs: [item.id])
        }
        applySelectionAfterDeletion(fallbackID: fallbackSelectionID)
        StorageManager.shared.deleteRecord(hash: item.contentHash)
    }
}
