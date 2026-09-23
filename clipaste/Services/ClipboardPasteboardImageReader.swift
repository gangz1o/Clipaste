import AppKit
import UniformTypeIdentifiers

enum ClipboardPasteboardImageReader {
    @MainActor
    static func imageData(from item: NSPasteboardItem) -> Data? {
        // Keep screenshot formats first, then accept other advertised image formats
        // (for example JPEG from messaging apps). A bad representation must not
        // hide a valid representation later in the list.
        let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        let otherImageTypes = item.types.filter { type in
            !preferredTypes.contains(type)
                && UTType(type.rawValue)?.conforms(to: .image) == true
        }

        for type in preferredTypes + otherImageTypes {
            guard let data = item.data(forType: type),
                  data.count <= ClipboardImageResourcePolicy.maximumStoredImageByteCount else {
                continue
            }
            let metadata = ImageProcessor.metadata(for: data)
            if ClipboardImageResourcePolicy.allowsStoredImage(metadata) {
                return data
            }
        }
        return nil
    }
}
