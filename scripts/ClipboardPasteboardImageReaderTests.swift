import AppKit
import UniformTypeIdentifiers

@main
enum ClipboardPasteboardImageReaderTests {
    @MainActor
    static func main() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        var pixel = [255, 0, 0]
        for y in 0..<6 {
            for x in 0..<8 { bitmap.setPixel(&pixel, atX: x, y: y) }
        }
        let png = bitmap.representation(using: .png, properties: [:])!
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let tiff = bitmap.tiffRepresentation!
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)

        for (type, data) in [(NSPasteboard.PasteboardType.png, png), (.tiff, tiff), (jpegType, jpeg)] {
            let item = NSPasteboardItem()
            item.setData(data, forType: type)
            let result = ClipboardPasteboardImageReader.imageData(from: item)
            precondition(result == data, "Must capture \(type.rawValue)")
            precondition(ImageProcessor.generateThumbnail(from: result!) != nil)
        }

        let invalidPNG = NSPasteboardItem()
        invalidPNG.setData(Data("invalid image".utf8), forType: .png)
        invalidPNG.setData(tiff, forType: .tiff)
        precondition(ClipboardPasteboardImageReader.imageData(from: invalidPNG) == tiff)
        invalidPNG.setData(Data(), forType: .tiff)
        invalidPNG.setData(jpeg, forType: jpegType)
        precondition(ClipboardPasteboardImageReader.imageData(from: invalidPNG) == jpeg)

        let textOnly = NSPasteboardItem()
        textOnly.setString("ordinary text", forType: .string)
        precondition(ClipboardPasteboardImageReader.imageData(from: textOnly) == nil)

        let url = FileManager.default.temporaryDirectory.appending(path: "image-\(UUID()).jpeg")
        defer { try? FileManager.default.removeItem(at: url) }
        try jpeg.write(to: url)
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(png, forType: .png)
        let captured = ClipboardImageSource.fileURL(
            url, fallbackData: ClipboardPasteboardImageReader.imageData(from: item)
        )
        precondition(captured.loadImageData() == jpeg, "Readable original must beat preview/icon data")
        try FileManager.default.removeItem(at: url)
        precondition(captured.loadImageData() == png, "Expired temporary file must use captured image bytes")
        precondition(ClipboardImageSource.fileURL(url, fallbackData: nil).loadImageData() == nil)
        try Data("broken file".utf8).write(to: url)
        precondition(captured.loadImageData() == png, "Invalid file must use captured image bytes")
        print("ClipboardPasteboardImageReaderTests passed")
    }
}
