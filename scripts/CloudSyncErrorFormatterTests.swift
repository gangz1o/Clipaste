import CloudKit
import Foundation

@main
enum CloudSyncErrorFormatterTests {
    static func main() {
        let recordID = CKRecord.ID(recordName: "record")
        let itemError = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Cannot create or modify field 'CD_topPinOrder' in record 'CD_ClipboardRecord' in production schema"
        ])
        let partialFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue, userInfo: [
            CKPartialErrorsByItemIDKey: [recordID: itemError]
        ])

        let direct = CloudSyncErrorFormatter.message(for: partialFailure)
        precondition(direct.contains("CD_topPinOrder"), "partial failure must expose per-item reasons: \(direct)")
        precondition(direct.contains("CloudKit schema"), "missing production fields must explain the schema cause: \(direct)")

        // Core Data wraps the CKError; the per-item reasons must still surface.
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: partialFailure])
        let nested = CloudSyncErrorFormatter.message(for: wrapped)
        precondition(nested.contains("CD_topPinOrder"), "wrapped partial failure must be unwrapped: \(nested)")

        let plain = CloudSyncErrorFormatter.message(for: NSError(domain: "Test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "plain failure"
        ]))
        precondition(plain == "plain failure")

        print("CloudSyncErrorFormatterTests passed")
    }
}
