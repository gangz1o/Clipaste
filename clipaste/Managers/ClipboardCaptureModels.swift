import AppKit
import Foundation
import os

extension ClipboardMonitor {
    enum Keys {
        static let isMonitoringPaused = "isMonitoringPaused"
        static let monitorInterval = "monitorInterval"
        static let recordsUniversalClipboard = "recordsUniversalClipboard"
    }

    enum DefaultValues {
        static let monitorInterval: TimeInterval = 0.5
        static let recordsUniversalClipboard = true
    }
}

struct ClipboardRecordPayload: Sendable {
    let hash: String
    let text: String?
    let appID: String?
    let appName: String?
    let type: String
    let rtfData: Data?
    let richTextArchive: ClipboardRichTextArchive?
    let sourcePlatformRawValue: String
    let sourceDeviceName: String?
    let captureMethodRawValue: String
    let captureSessionID: UUID?
}

struct ClipboardImagePayload: Sendable {
    let source: ClipboardImageSource
    let fallbackRecordPayload: ClipboardRecordPayload?
    let appID: String?
    let appName: String?
    let sourcePlatformRawValue: String
    let sourceDeviceName: String?
    let captureMethodRawValue: String
    let captureSessionID: UUID?
}

extension Notification.Name {
    nonisolated static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
    nonisolated static let didFinishDataMigration = Notification.Name("com.clipaste.didFinishDataMigration")
}
