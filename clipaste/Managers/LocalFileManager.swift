import Foundation

final class LocalFileManager {
    static let shared = LocalFileManager()

    private let appSupportDirectory: URL
    private let originalsDirectory: URL
    private let thumbnailsDirectory: URL

    private init() {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Application Support directory.")
        }

        let appDirectoryName = Bundle.main.bundleIdentifier ?? "clipaste"
        let appSupportDirectory = applicationSupportURL.appendingPathComponent(appDirectoryName, isDirectory: true)
        let originalsDirectory = appSupportDirectory.appendingPathComponent("Originals", isDirectory: true)
        let thumbnailsDirectory = appSupportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)

        do {
            try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Unable to prepare image storage directories: \(error)")
        }

        self.appSupportDirectory = appSupportDirectory
        self.originalsDirectory = originalsDirectory
        self.thumbnailsDirectory = thumbnailsDirectory
    }

    nonisolated
    func saveImagePayload(data: Data, hash: String) async throws -> (originalPath: String, thumbnailPath: String) {
        let originalsDirectory = self.originalsDirectory
        let thumbnailsDirectory = self.thumbnailsDirectory

        return try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let originalFileName = "\(hash).data"
            let thumbnailFileName = "\(hash)_thumb.png"
            let originalURL = originalsDirectory.appendingPathComponent(originalFileName)
            let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)

            if !fileManager.fileExists(atPath: originalURL.path) {
                try data.write(to: originalURL, options: .atomic)
            }

            if !fileManager.fileExists(atPath: thumbnailURL.path) {
                guard let thumbnailData = ImageProcessor.generateThumbnail(from: data) else {
                    throw LocalFileManagerError.thumbnailGenerationFailed
                }

                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            }

            return (
                originalPath: "Originals/\(originalFileName)",
                thumbnailPath: "Thumbnails/\(thumbnailFileName)"
            )
        }.value
    }

    nonisolated
    func url(forRelativePath relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }

        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }

        return appSupportDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    nonisolated
    func data(forRelativePath relativePath: String?) async throws -> Data {
        guard let fileURL = url(forRelativePath: relativePath) else {
            throw LocalFileManagerError.invalidFilePath
        }

        return try await Task.detached(priority: .utility) {
            try Data(contentsOf: fileURL)
        }.value
    }
}

private enum LocalFileManagerError: Error {
    case thumbnailGenerationFailed
    case invalidFilePath
}
