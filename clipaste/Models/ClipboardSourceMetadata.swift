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
    static let currentPlatform = ClipboardSourcePlatform.macOS.rawValue
    static let macOSMonitorMethod = ClipboardCaptureMethod.monitor.rawValue
    static let manualMethod = ClipboardCaptureMethod.manual.rawValue
    static let importedMethod = ClipboardCaptureMethod.imported.rawValue
    static let generatedMethod = ClipboardCaptureMethod.generated.rawValue

    static var currentDeviceName: String? {
        #if os(macOS)
        Host.current().localizedName
        #else
        nil
        #endif
    }
}
