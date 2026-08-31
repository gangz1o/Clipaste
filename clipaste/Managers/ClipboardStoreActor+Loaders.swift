import Foundation
import SwiftData

extension ClipboardStoreActor {
    func loadPreviewImageData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.previewImageData
    }

    func loadPlainText(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.resolvedPlainText
    }

    func loadAppIconDominantColorHex(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.appIconDominantColorHex
    }

    func loadAppIconData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.appIconData
    }

    func loadPasteRecord(id: UUID) -> ClipboardPasteRecord? {
        guard let record = fetchStoredRecord(id: id) else {
            return nil
        }

        return ClipboardPasteRecord(
            id: record.id,
            typeRawValue: record.typeRawValue,
            plainText: record.resolvedPlainText,
            rtfData: record.rtfData,
            richTextArchiveData: record.richTextArchiveData
        )
    }

    func loadOriginalImageData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.imageData
    }

    func loadImageData(id: UUID) -> Data? {
        if let record = fetchStoredRecord(id: id) {
            return record.imageData ?? record.previewImageData
        }
        return nil
    }

    func loadRTFData(id: UUID) -> Data? {
        fetchStoredRecord(id: id)?.rtfData
    }

    func loadImageUTType(id: UUID) -> String? {
        fetchStoredRecord(id: id)?.imageUTType
    }
}
