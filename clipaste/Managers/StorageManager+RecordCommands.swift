import Foundation
import SwiftData

extension StorageManager {
    func recordExists(hash: String) async -> Bool {
        let actor = storeActor
        return await detachedRead {
            await actor.recordExists(hash: hash)
        }
    }

    nonisolated
    func upsertRecord(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        appIconDominantColorHex: String? = nil,
        appIconData: Data? = nil,
        type: String,
        rtfData: Data? = nil,
        richTextArchiveData: Data? = nil,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil,
        sourcePlatformRawValue: String,
        sourceDeviceName: String?,
        captureMethodRawValue: String,
        captureSessionID: UUID? = nil
    ) {
        let actor = self.storeActor

        spawnTrackedTask(priority: .userInitiated) {
            await actor.upsert(
                hash: hash,
                text: text,
                appID: appID,
                appName: appName,
                appIconDominantColorHex: appIconDominantColorHex,
                appIconData: appIconData,
                type: type,
                rtfData: rtfData,
                richTextArchiveData: richTextArchiveData,
                previewImageData: previewImageData,
                imageData: imageData,
                imageMetadata: imageMetadata,
                sourcePlatformRawValue: sourcePlatformRawValue,
                sourceDeviceName: sourceDeviceName,
                captureMethodRawValue: captureMethodRawValue,
                captureSessionID: captureSessionID
            )
        }
    }

    nonisolated
    func upsertRecordAndWait(
        hash: String,
        text: String?,
        appID: String?,
        appName: String?,
        appIconDominantColorHex: String? = nil,
        appIconData: Data? = nil,
        type: String,
        rtfData: Data? = nil,
        richTextArchiveData: Data? = nil,
        previewImageData: Data? = nil,
        imageData: Data? = nil,
        imageMetadata: ClipboardImageMetadata? = nil,
        sourcePlatformRawValue: String,
        sourceDeviceName: String?,
        captureMethodRawValue: String,
        captureSessionID: UUID? = nil
    ) async {
        guard acceptsNewTasks else { return }
        await storeActor.upsert(
            hash: hash,
            text: text,
            appID: appID,
            appName: appName,
            appIconDominantColorHex: appIconDominantColorHex,
            appIconData: appIconData,
            type: type,
            rtfData: rtfData,
            richTextArchiveData: richTextArchiveData,
            previewImageData: previewImageData,
            imageData: imageData,
            imageMetadata: imageMetadata,
            sourcePlatformRawValue: sourcePlatformRawValue,
            sourceDeviceName: sourceDeviceName,
            captureMethodRawValue: captureMethodRawValue,
            captureSessionID: captureSessionID
        )
    }

    nonisolated
    func performAutoCleanup(before expirationDate: Date) {
        let actor = self.cleanupActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.cleanUpExpiredRecords(before: expirationDate)
        }
    }

    nonisolated
    func deleteRecord(hash: String) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.delete(hash: hash)
        }
    }

    nonisolated
    func togglePin(hash: String, isPinned: Bool) {
        let actor = self.storeActor
        spawnTrackedTask(priority: .userInitiated) {
            await actor.updatePinStatus(hash: hash, isPinned: isPinned)
        }
    }

    nonisolated
    func processOCRForImage(hash: String, imageData: Data) {
        spawnTrackedTask(priority: .background) {
            guard let text = await OCREngine.extractText(from: imageData) else { return }
            guard Task.isCancelled == false else { return }
            let container = self.container
            let ocrActor = ClipboardStoreActor(modelContainer: container)
            await ocrActor.updateRecordWithOCRText(hash: hash, text: text)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.enrichment.rawValue
                    ]
                )
            }
        }
    }

    nonisolated
    func processLinkMetadata(hash: String, urlString: String) {
        spawnTrackedTask(priority: .background, linkMetadataHash: hash) {
            let (title, iconData) = await LinkMetadataEngine.fetchMetadata(for: urlString)
            guard Task.isCancelled == false else { return }

            let fetchedMetadata = title != nil || iconData != nil
            if fetchedMetadata {
                let container = self.container
                let linkActor = ClipboardStoreActor(modelContainer: container)
                await linkActor.updateRecordWithLinkMetadata(hash: hash, title: title, iconData: iconData)
            }
            guard Task.isCancelled == false else { return }

            let retryDelay = self.recordLinkMetadataOutcome(
                hash: hash,
                succeeded: fetchedMetadata
            )

            if fetchedMetadata {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .clipboardRecordDidChange,
                        object: nil,
                        userInfo: [
                            "contentHash": hash,
                            "kind": ClipboardRecordChangeKind.enrichment.rawValue
                        ]
                    )
                }
            } else if let retryDelay {
                self.scheduleLinkMetadataRetry(
                    hash: hash,
                    urlString: urlString,
                    delay: retryDelay
                )
            }
        }
    }

    nonisolated
    func processSyntaxHighlight(hash: String, text: String) {
        spawnTrackedTask(priority: .background) {
            guard let rtfData = await SyntaxHighlightService.shared.processAndHighlight(text: text) else { return }
            guard Task.isCancelled == false else { return }
            let container = self.container
            let highlightActor = ClipboardStoreActor(modelContainer: container)
            await highlightActor.updateRecordWithRTFData(hash: hash, rtfData: rtfData)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .clipboardRecordDidChange,
                    object: nil,
                    userInfo: [
                        "contentHash": hash,
                        "kind": ClipboardRecordChangeKind.enrichment.rawValue
                    ]
                )
            }
        }
    }
}
