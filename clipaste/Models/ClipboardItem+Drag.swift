import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ClipboardItem {
    var universalDragProvider: NSItemProvider {
        let provider: NSItemProvider
        let plainText = rawText ?? (textPreview.isEmpty ? nil : textPreview)

        if contentType == .image, let imageFileURL = originalImageURL ?? thumbnailURL {
            provider = NSItemProvider(object: imageFileURL as NSURL)

            if let image = NSImage(contentsOf: imageFileURL) {
                provider.registerObject(image, visibility: .all)
            }
        } else if isFastLink,
                  let text = plainText,
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            provider = NSItemProvider(object: url as NSURL)
            provider.registerObject(text as NSString, visibility: .all)
        } else if let text = plainText {
            provider = NSItemProvider(object: text as NSString)
        } else if contentType == .fileURL, let path = fileURL {
            let resolvedURL: URL

            if let url = URL(string: path), url.scheme != nil {
                resolvedURL = url
            } else {
                resolvedURL = URL(fileURLWithPath: path)
            }

            provider = NSItemProvider(object: resolvedURL as NSURL)
        } else {
            provider = NSItemProvider()
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: "com.seedpilot.clipboard.item",
            visibility: .all
        ) { [id] completion in
            completion(id.uuidString.data(using: .utf8), nil)
            return nil
        }

        return provider
    }
}
