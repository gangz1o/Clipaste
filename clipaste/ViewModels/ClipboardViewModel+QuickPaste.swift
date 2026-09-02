import AppKit
import Foundation

extension ClipboardViewModel {
    func updateQuickPasteTargets(indexesByItemID: [UUID: Int]) {
        let targets = indexesByItemID
            .sorted { lhs, rhs in lhs.value < rhs.value }
            .map(\.key)

        guard targets != quickPasteTargetsByNumber else { return }
        quickPasteTargetsByNumber = targets
    }

    func clearQuickPasteTargets() {
        guard quickPasteTargetsByNumber.isEmpty == false else { return }
        quickPasteTargetsByNumber = []
    }

    func handleQuickPasteShortcut(_ event: NSEvent) -> Bool {
        guard let index = quickPasteIndex(for: event) else { return false }

        let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let pressedModifiers = event.modifierFlags.intersection(relevantMask)
        let quickPasteModifiers = quickPasteModifier.eventFlags
        let plainTextModifiers = quickPasteModifiers.union(plainTextModifier.eventFlags)
        let shouldPasteAsPlainText = plainTextModifiers != quickPasteModifiers
            && pressedModifiers == plainTextModifiers

        guard pressedModifiers == quickPasteModifiers || shouldPasteAsPlainText else {
            return false
        }
        guard quickPasteTargetsByNumber.indices.contains(index) else { return false }
        guard let item = item(for: quickPasteTargetsByNumber[index]) else { return false }

        if shouldPasteAsPlainText {
            pasteAsPlainText(item: item)
        } else {
            pasteToActiveApp(item: item)
        }
        return true
    }

    private func quickPasteIndex(for event: NSEvent) -> Int? {
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              (1...9).contains(number) else {
            return nil
        }
        return number - 1
    }
}
