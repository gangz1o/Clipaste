import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardFileReference {
    nonisolated
    static func resolvedURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: trimmed)
    }

    nonisolated
    static func resolvedPath(from rawValue: String?) -> String? {
        resolvedURL(from: rawValue)?.path
    }

    nonisolated
    static func isLikelyImageFileReference(_ rawValue: String?) -> Bool {
        guard let fileURL = resolvedURL(from: rawValue) else { return false }
        return isLikelyImageFileURL(fileURL)
    }

    nonisolated
    static func isLikelyImageFileURL(_ fileURL: URL) -> Bool {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
            return false
        }

        return type.conforms(to: .image)
    }

    nonisolated
    static func loadImageData(from rawValue: String?) -> Data? {
        guard let fileURL = resolvedURL(from: rawValue) else { return nil }
        return loadImageData(from: fileURL)
    }

    nonisolated
    static func loadImageData(from fileURL: URL) -> Data? {
        let isImageByType: Bool = {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
                  let contentType = resourceValues.contentType else {
                return false
            }

            return contentType.conforms(to: .image)
        }()

        guard isImageByType || isLikelyImageFileURL(fileURL) else { return nil }
        guard let data = accessibleData(
            from: fileURL,
            maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
        ) else {
            return nil
        }
        let metadata = ImageProcessor.metadata(for: data)
        guard ClipboardImageResourcePolicy.allowsStoredImage(metadata) else { return nil }
        return data
    }

    nonisolated
    static func accessibleData(
        from fileURL: URL,
        maximumByteCount: Int
    ) -> Data? {
        let didStartSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard maximumByteCount > 0,
              let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0,
              fileSize <= maximumByteCount,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe, .uncached]),
              data.count <= maximumByteCount else {
            return nil
        }

        return data
    }
}
