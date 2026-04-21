import AppKit
import Foundation

/// Stores a curated set of pasteboard text representations so we can
/// restore rich content without persisting every app-private pasteboard type.
struct ClipboardRichTextArchive: Codable, Sendable {
    struct Representation: Codable, Sendable {
        let pasteboardTypeRawValue: String
        let data: Data

        private enum CodingKeys: String, CodingKey {
            case pasteboardTypeRawValue
            case data
        }

        nonisolated
        init(pasteboardTypeRawValue: String, data: Data) {
            self.pasteboardTypeRawValue = pasteboardTypeRawValue
            self.data = data
        }

        nonisolated
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.pasteboardTypeRawValue = try container.decode(String.self, forKey: .pasteboardTypeRawValue)
            self.data = try container.decode(Data.self, forKey: .data)
        }

        nonisolated
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pasteboardTypeRawValue, forKey: .pasteboardTypeRawValue)
            try container.encode(data, forKey: .data)
        }

        nonisolated
        var pasteboardType: NSPasteboard.PasteboardType {
            NSPasteboard.PasteboardType(pasteboardTypeRawValue)
        }
    }

    let representations: [Representation]

    private enum CodingKeys: String, CodingKey {
        case representations
    }

    nonisolated
    init(representations: [Representation]) {
        var seenTypes: Set<String> = []
        self.representations = representations.filter { representation in
            guard representation.data.isEmpty == false else {
                return false
            }

            return seenTypes.insert(representation.pasteboardTypeRawValue).inserted
        }
    }

    nonisolated
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(representations: try container.decode([Representation].self, forKey: .representations))
    }

    nonisolated
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(representations, forKey: .representations)
    }

    nonisolated
    var isEmpty: Bool {
        representations.isEmpty
    }

    nonisolated
    var previewRTFData: Data? {
        data(for: .rtf)
    }

    nonisolated
    var orderedPasteboardTypes: [NSPasteboard.PasteboardType] {
        representations.map(\.pasteboardType)
    }

    nonisolated
    var hasComplexPreviewRepresentations: Bool {
        representations.contains { representation in
            switch representation.pasteboardType {
            case .html, .rtfd, .tabularText:
                return true
            default:
                return false
            }
        }
    }

    nonisolated
    func data(for pasteboardType: NSPasteboard.PasteboardType) -> Data? {
        representations.first(where: { $0.pasteboardTypeRawValue == pasteboardType.rawValue })?.data
    }

    nonisolated
    func encodedData() -> Data? {
        guard isEmpty == false else {
            return nil
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(self)
    }

    nonisolated
    static func decode(from encodedData: Data?) -> ClipboardRichTextArchive? {
        guard let encodedData, encodedData.isEmpty == false else {
            return nil
        }

        let decoder = PropertyListDecoder()
        return try? decoder.decode(Self.self, from: encodedData)
    }

    nonisolated
    static func fromPasteboardItem(_ pasteboardItem: NSPasteboardItem) -> ClipboardRichTextArchive? {
        let representations: [Representation] = supportedPasteboardTypes.compactMap { pasteboardType in
            guard let data = pasteboardItem.data(forType: pasteboardType), data.isEmpty == false else {
                return nil
            }

            return Representation(
                pasteboardTypeRawValue: pasteboardType.rawValue,
                data: data
            )
        }

        let archive = ClipboardRichTextArchive(representations: representations)
        return archive.isEmpty ? nil : archive
    }

    nonisolated
    static func fromRTFData(_ rtfData: Data) -> ClipboardRichTextArchive? {
        guard rtfData.isEmpty == false else {
            return nil
        }

        return ClipboardRichTextArchive(
            representations: [
                Representation(
                    pasteboardTypeRawValue: NSPasteboard.PasteboardType.rtf.rawValue,
                    data: rtfData
                ),
            ]
        )
    }
}

private extension ClipboardRichTextArchive {
    nonisolated
    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .html,
        .rtf,
        .rtfd,
        .tabularText,
    ]
}
