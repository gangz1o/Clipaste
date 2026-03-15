import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PasteEngine {
    static let shared = PasteEngine()

    private let pasteboard = NSPasteboard.general
    private let vKeyCode: CGKeyCode = 0x09

    private init() {}

    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func writeToPasteboard(record: ClipboardRecord) async -> Bool {
        guard let payload = await Self.makePastePayload(
            recordID: record.id,
            typeRawValue: record.typeRawValue,
            plainText: record.plainText
        ) else { return false }

        ClipboardMonitor.shared.isIgnoredNextChange = true
        pasteboard.clearContents()
        return write(payload: payload)
    }

    /// 仅将纯文本写入系统剪贴板（抹除一切格式）
    func writePlainTextToPasteboard(text: String) {
        ClipboardMonitor.shared.isIgnoredNextChange = true
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func simulateCommandV() {
        postPasteKeystroke()
    }

    func paste(record: ClipboardRecord) async {
        guard checkAccessibilityPermissions() else { return }
        guard await writeToPasteboard(record: record) else { return }
        ClipboardPanelManager.shared.hidePanel()
        try? await Task.sleep(nanoseconds: 150_000_000)
        simulateCommandV()
    }

    private func write(payload: PastePayload) -> Bool {
        switch payload {
        case let .text(text):
            return pasteboard.setString(text, forType: .string)
        case let .fileURL(url):
            return pasteboard.writeObjects([url as NSURL])
        case let .image(data, format):
            return pasteboard.setData(data, forType: format.pasteboardType)
        }
    }

    private func postPasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    nonisolated
    private static func makePastePayload(
        recordID: UUID,
        typeRawValue: String,
        plainText: String?
    ) async -> PastePayload? {
        guard let contentType = ClipboardContentType(rawValue: typeRawValue) else { return nil }

        switch contentType {
        case .text, .color, .link, .code:
            guard let plainText, !plainText.isEmpty else { return nil }
            return .text(plainText)
        case .fileURL:
            guard let plainText, !plainText.isEmpty else { return nil }

            if let url = URL(string: plainText), url.isFileURL {
                return .fileURL(url)
            }

            return .fileURL(URL(fileURLWithPath: plainText))
        case .image:
            let imageData = await StorageManager.shared.loadImageData(id: recordID)
            let previewData = await StorageManager.shared.loadPreviewImageData(id: recordID)

            guard let data = imageData ?? previewData else {
                return nil
            }

            return .image(data, detectImageFormat(for: data))
        }
    }

    nonisolated
    private static func detectImageFormat(for data: Data) -> ImageFormat {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        }

        return .tiff
    }

    /// 将图片格式转换后写入系统剪贴板（PNG / TIFF / JPG）
    func convertImageAndCopyToClipboard(item: ClipboardItem, targetFormat: String) {
        guard item.contentType == .image else { return }

        Task {
            let imageData = await StorageManager.shared.loadImageData(id: item.id)
            let previewData = await StorageManager.shared.loadPreviewImageData(id: item.id)

            guard let sourceData = imageData ?? previewData,
                  let originalImage = NSImage(data: sourceData),
                  let tiffRepresentation = originalImage.tiffRepresentation,
                  let bitmapImageRep = NSBitmapImageRep(data: tiffRepresentation) else {
                return
            }

            let convertedData: Data?
            let pbType: NSPasteboard.PasteboardType

            switch targetFormat {
            case "PNG":
                convertedData = bitmapImageRep.representation(using: .png, properties: [:])
                pbType = .png
            case "TIFF":
                convertedData = tiffRepresentation
                pbType = .tiff
            case "JPG":
                convertedData = bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                pbType = NSPasteboard.PasteboardType("public.jpeg")
            default:
                convertedData = bitmapImageRep.representation(using: .png, properties: [:])
                pbType = .png
            }

            guard let finalData = convertedData else { return }

            ClipboardMonitor.shared.isIgnoredNextChange = true
            pasteboard.clearContents()
            pasteboard.setData(finalData, forType: pbType)
            NSSound(named: "Pop")?.play()
        }
    }
}

private enum PastePayload: Sendable {
    case text(String)
    case fileURL(URL)
    case image(Data, ImageFormat)
}

private enum ImageFormat: Sendable {
    case png
    case tiff

    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png:
            return .png
        case .tiff:
            return .tiff
        }
    }
}
