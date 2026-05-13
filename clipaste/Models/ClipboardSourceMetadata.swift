import Foundation

enum ClipboardSourcePlatform: String, Sendable {
    case macOS
    case iOS
}

enum ClipboardCaptureMethod: String, Sendable {
    case monitor
    case foreground
    case background
    case manual
    case imported
    case generated
}

enum ClipboardSourceMetadata {
    nonisolated static let currentPlatform = ClipboardSourcePlatform.macOS.rawValue
    nonisolated static let macOSMonitorMethod = ClipboardCaptureMethod.monitor.rawValue
    nonisolated static let manualMethod = ClipboardCaptureMethod.manual.rawValue
    nonisolated static let importedMethod = ClipboardCaptureMethod.imported.rawValue
    nonisolated static let generatedMethod = ClipboardCaptureMethod.generated.rawValue

    nonisolated static var currentDeviceName: String? {
        #if os(macOS)
        Host.current().localizedName
        #else
        nil
        #endif
    }
}
