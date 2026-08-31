import AppKit
import Foundation
import os

@MainActor
extension ClipboardMonitor {
    func pollPasteboardIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        if isIgnoredNextChange {
            isIgnoredNextChange = false
            lastChangeCount = changeCount
            return
        }

        lastChangeCount = changeCount
        processPasteboardItems()
    }

    func processPasteboardItems() {
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let appID = sourceApplication?.bundleIdentifier
        let appName = sourceApplication?.localizedName
        // 优先走缓存（按 bundleID 命中已编码好的 PNG），缺 bundleID 才回退到
        // 当前进程图标重新编码 —— 极少发生，但保留兜底以兼容老路径。
        let sourceAppIconData = AppIconManager.shared.iconPNGData(
            for: appID,
            fallbackImage: sourceApplication?.icon
        )
        let sourcePlatformRawValue = ClipboardSourceMetadata.currentPlatform
        let sourceDeviceName = ClipboardSourceMetadata.currentDeviceName
        let captureMethodRawValue = ClipboardSourceMetadata.macOSMonitorMethod
        let shouldFetchLinkMetadata = ClipboardLinkDisplayMode.shouldFetchMetadata(defaults: defaults)

        if let appID, ignoredBundleIdentifiers.contains(appID) {
            return
        }

        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return }
        let storage = StorageManager.shared
        var recordPayloads: [ClipboardRecordPayload] = []
        var imagePayloads: [ClipboardImagePayload] = []

        for pasteboardItem in pasteboardItems {
            if let fileURL = imageFileURL(from: pasteboardItem) {
                imagePayloads.append(
                    ClipboardImagePayload(
                        source: .fileURL(fileURL),
                        fallbackRecordPayload: makeFileURLPayload(
                            from: pasteboardItem,
                            appID: appID,
                            appName: appName,
                            sourcePlatformRawValue: sourcePlatformRawValue,
                            sourceDeviceName: sourceDeviceName,
                            captureMethodRawValue: captureMethodRawValue
                        ),
                        appID: appID,
                        appName: appName,
                        sourcePlatformRawValue: sourcePlatformRawValue,
                        sourceDeviceName: sourceDeviceName,
                        captureMethodRawValue: captureMethodRawValue,
                        captureSessionID: captureSessionID
                    )
                )
                continue
            }

            let textPayload = makeTextPayload(
                from: pasteboardItem,
                appID: appID,
                appName: appName,
                sourcePlatformRawValue: sourcePlatformRawValue,
                sourceDeviceName: sourceDeviceName,
                captureMethodRawValue: captureMethodRawValue
            )

            if let imageData = imageData(from: pasteboardItem) {
                if let textPayload, shouldPreferTextPayload(textPayload, overImageFrom: pasteboardItem) {
                    recordPayloads.append(textPayload)
                } else {
                    imagePayloads.append(
                        ClipboardImagePayload(
                            source: .data(imageData),
                            fallbackRecordPayload: nil,
                            appID: appID,
                            appName: appName,
                            sourcePlatformRawValue: sourcePlatformRawValue,
                            sourceDeviceName: sourceDeviceName,
                            captureMethodRawValue: captureMethodRawValue,
                            captureSessionID: captureSessionID
                        )
                    )
                }
                continue
            }

            if let payload = makeFileURLPayload(
                from: pasteboardItem,
                appID: appID,
                appName: appName,
                sourcePlatformRawValue: sourcePlatformRawValue,
                sourceDeviceName: sourceDeviceName,
                captureMethodRawValue: captureMethodRawValue
            ) {
                recordPayloads.append(payload)
                continue
            }

            if let payload = textPayload {
                recordPayloads.append(payload)
            }
        }

        guard imagePayloads.isEmpty == false || recordPayloads.isEmpty == false else {
            return
        }

        let capturedRecordPayloads = recordPayloads
        let capturedImagePayloads = imagePayloads
        enqueuePersistenceTask {
            await Self.persistCapturedPayloads(
                storage: storage,
                recordPayloads: capturedRecordPayloads,
                imagePayloads: capturedImagePayloads,
                sourceAppIconData: sourceAppIconData,
                shouldFetchLinkMetadata: shouldFetchLinkMetadata
            )
        }
    }

}
