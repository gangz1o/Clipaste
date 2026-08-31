import Foundation

@main
enum ClipboardImageResourcePolicyTests {
    static func main() throws {
        testMetadataBudgets()
        try testOversizedSparseFileIsRejectedBeforeRead()
        try testProductionImagePathsStayBounded()
        print("ClipboardImageResourcePolicyTests passed")
    }

    private static func testMetadataBudgets() {
        let allowed = ClipboardImageMetadata(
            utTypeIdentifier: "public.png",
            byteCount: 1_024,
            pixelWidth: 2_000,
            pixelHeight: 2_000
        )
        precondition(ClipboardImageResourcePolicy.allowsStoredImage(allowed))

        let oversizedBytes = ClipboardImageMetadata(
            utTypeIdentifier: "public.png",
            byteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount + 1,
            pixelWidth: 1,
            pixelHeight: 1
        )
        precondition(ClipboardImageResourcePolicy.allowsStoredImage(oversizedBytes) == false)

        let oversizedPixels = ClipboardImageMetadata(
            utTypeIdentifier: "public.png",
            byteCount: 1_024,
            pixelWidth: 20_000,
            pixelHeight: 20_000
        )
        precondition(ClipboardImageResourcePolicy.allowsStoredImage(oversizedPixels) == false)
        precondition(
            ClipboardImageResourcePolicy.boundedScreenPinPixelSize(Int.max)
                == ClipboardImageResourcePolicy.maximumScreenPinPixelSize
        )
    }

    private static func testOversizedSparseFileIsRejectedBeforeRead() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipaste-image-budget-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x89]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(ClipboardImageResourcePolicy.maximumStoredImageByteCount + 1))
        try handle.close()

        let data = ClipboardFileReference.accessibleData(
            from: fileURL,
            maximumByteCount: ClipboardImageResourcePolicy.maximumStoredImageByteCount
        )
        precondition(data == nil)
    }

    private static func testProductionImagePathsStayBounded() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let managersURL = root.appendingPathComponent("clipaste/Managers", isDirectory: true)
        let pipeline = try FileManager.default.contentsOfDirectory(
            at: managersURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent.hasPrefix("ClipboardImagePipeline") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
        let ocr = try String(
            contentsOf: root.appendingPathComponent("clipaste/Managers/OCREngine.swift"),
            encoding: .utf8
        )

        precondition(pipeline.contains("ImageProcessor.downsampleImage"))
        precondition(pipeline.contains("from: fileURL"))
        precondition(pipeline.contains("metadata(for: fileURL"))
        precondition(pipeline.contains("allowsStoredImage(metadata)"))
        precondition(pipeline.contains("loadScreenPinFileDataOffMain") == false)
        precondition(pipeline.contains("data.append(chunk)") == false)
        precondition(ocr.contains("downsampledCGImage"))
        precondition(ocr.contains("maximumOCRPixelSize"))
        precondition(ocr.contains("CGImageSourceCreateImageAtIndex") == false)
    }
}
