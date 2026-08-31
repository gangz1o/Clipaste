import AppKit
import SwiftUI

extension ClipboardViewModel {
    var shouldForcePlainTextOutput: Bool {
        if isPlainTextModifierHeld {
            return true
        }

        return pasteTextFormat == .plainText
    }

    func pasteRecord(for item: ClipboardItem) async -> ClipboardPasteRecord? {
        if let record = visibleItemPasteRecord(for: item) {
            return record
        }

        return await StorageManager.shared.loadPasteRecord(id: item.id)
    }

    func plainText(for item: ClipboardItem) async -> String? {
        if let text = fullVisibleText(for: item) {
            return text
        }

        return await StorageManager.shared.loadPlainText(id: item.id)
    }

    func visibleItemPasteRecord(for item: ClipboardItem) -> ClipboardPasteRecord? {
        if shouldForcePlainTextOutput == false, item.hasRTF {
            return nil
        }

        guard let text = fullVisibleText(for: item) else {
            return nil
        }

        return ClipboardPasteRecord(
            id: item.id,
            typeRawValue: item.contentType.rawValue,
            plainText: text,
            rtfData: nil,
            richTextArchiveData: nil
        )
    }

    func fullVisibleText(for item: ClipboardItem) -> String? {
        let text: String?
        switch item.contentType {
        case .text, .link, .code:
            text = item.rawText
        case .color:
            text = item.textPreview.isEmpty ? nil : item.textPreview
        case .fileURL:
            text = item.fileURL
        case .image:
            return nil
        }

        guard let text, text.count < 500 else {
            return nil
        }

        return text
    }

    func moveItemToTop(_ item: ClipboardItem) {
        if let index = itemIndexByID[item.id], index != 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                moveItem(withID: item.id, to: 0)
            }
        }
        selectedItemIDs = [item.id]
        lastSelectedID = item.id

        Task {
            await StorageManager.shared.moveItemToTop(id: item.id)
        }
    }
}
