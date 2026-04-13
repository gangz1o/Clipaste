import Foundation
import Observation

@MainActor
@Observable
final class ClipboardItemTitleEditorViewModel {
    let itemID: UUID
    let originalTitle: String?
    let previewText: String

    var draftTitle: String

    init(item: ClipboardItem) {
        self.itemID = item.id
        self.originalTitle = item.trimmedCustomTitle
        self.draftTitle = item.trimmedCustomTitle ?? ""
        self.previewText = ClipboardItemTitleEditorViewModel.makePreviewText(for: item)
    }

    var sheetTitle: LocalizedStringResource {
        originalTitle == nil ? "Add Title" : "Edit Title"
    }

    var normalizedTitle: String? {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canSave: Bool {
        normalizedTitle != originalTitle
    }
}

private extension ClipboardItemTitleEditorViewModel {
    static func makePreviewText(for item: ClipboardItem) -> String {
        if let fileDisplayName = item.fileDisplayName, fileDisplayName.isEmpty == false {
            return fileDisplayName
        }

        if let rawText = item.rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
           rawText.isEmpty == false {
            return rawText
        }

        let preview = item.textPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty == false {
            return preview
        }

        return String(localized: "(Empty)")
    }
}
