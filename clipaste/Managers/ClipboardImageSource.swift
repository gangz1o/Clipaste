import Foundation

enum ClipboardImageSource: Sendable {
    case data(Data)
    case fileURL(URL, fallbackData: Data?)

    nonisolated func loadImageData() -> Data? {
        switch self {
        case let .data(data):
            return data
        case let .fileURL(fileURL, fallbackData):
            // Some apps publish a temporary file alongside an embedded image.
            // Preserve the original when readable, but don't depend on its lifetime.
            return ClipboardFileReference.loadImageData(from: fileURL) ?? fallbackData
        }
    }
}
