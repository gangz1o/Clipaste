import AppKit

struct ClipboardItem {
    let isScreenPinEligible: Bool
}

@MainActor
final class ClipboardImagePipeline {
    static let shared = ClipboardImagePipeline()

    func screenPinImage(for item: ClipboardItem, maxPixelSize: Int) async -> NSImage? {
        nil
    }

    func cancelScreenPinLoads() {}
}

@MainActor
final class ScreenPinWindowCoordinator: ScreenPinWindowCoordinating {
    static let shared = ScreenPinWindowCoordinator()

    func show(image: NSImage, at screenPoint: CGPoint, initialSizeScale: Double) {}
    func closeAll() {}
}

enum AppLanguage: String {
    case auto

    var resolvedLocale: Locale { .current }
}
