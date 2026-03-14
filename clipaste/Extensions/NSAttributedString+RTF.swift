import Foundation
import AppKit

extension NSAttributedString {
    /// Serialize this attributed string to RTF data.
    func toRTFData() -> Data? {
        try? data(
            from: NSRange(location: 0, length: length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Deserialize RTF data into an NSAttributedString.
    static func fromRTFData(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}
