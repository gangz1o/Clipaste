import AppKit
import ApplicationServices
import Foundation

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

    func paste(record: ClipboardRecord) async {
        guard checkAccessibilityPermissions() else { return }

        let snapshot = ClipboardRecordSnapshot(
            typeRawValue: record.typeRawValue,
            plainText: record.plainText,
            originalFilePath: record.originalFilePath
        )

        guard let payload = await Self.makePastePayload(from: snapshot) else { return }

        ClipboardPanelManager.shared.hidePanel()
        ClipboardMonitor.shared.isIgnoredNextChange = true
        pasteboard.clearContents()

        guard write(payload: payload) else { return }

        try? await Task.sleep(nanoseconds: 150_000_000)
        postPasteKeystroke()
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
    private static func makePastePayload(from snapshot: ClipboardRecordSnapshot) async -> PastePayload? {
        guard let contentType = ClipboardContentType(rawValue: snapshot.typeRawValue) else { return nil }

        switch contentType {
        case .text, .color:
            guard let plainText = snapshot.plainText, !plainText.isEmpty else { return nil }
            return .text(plainText)
        case .fileURL:
            guard let plainText = snapshot.plainText, !plainText.isEmpty else { return nil }

            if let url = URL(string: plainText), url.isFileURL {
                return .fileURL(url)
            }

            return .fileURL(URL(fileURLWithPath: plainText))
        case .image:
            guard let data = try? await LocalFileManager.shared.data(forRelativePath: snapshot.originalFilePath) else {
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
}

private struct ClipboardRecordSnapshot: Sendable {
    let typeRawValue: String
    let plainText: String?
    let originalFilePath: String?
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
