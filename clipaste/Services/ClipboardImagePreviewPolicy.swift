import CoreGraphics

enum ClipboardImagePreviewPolicy {
    nonisolated static var storedPreviewMaxPixelSize: Int { 2_000 }

    nonisolated static func quickLookDisplayMaxPixelSize(
        visibleFrame: CGRect,
        scaleFactor: CGFloat
    ) -> Int {
        let longestEdge = max(visibleFrame.width, visibleFrame.height)
        guard longestEdge > 0 else {
            return 1_800
        }

        let boundedEdge = longestEdge * 0.72 * scaleFactor
        return min(2_400, max(1_600, Int(boundedEdge.rounded(.up))))
    }

    nonisolated static func shouldUpgradeQuickLookImage(
        currentImageSize: CGSize,
        targetDisplaySize: CGSize,
        scaleFactor: CGFloat
    ) -> Bool {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else {
            return true
        }

        guard targetDisplaySize.width > 0, targetDisplaySize.height > 0 else {
            return false
        }

        let currentLongestEdge = max(currentImageSize.width, currentImageSize.height)
        let requiredLongestEdge = max(targetDisplaySize.width, targetDisplaySize.height) * scaleFactor

        // 留出一点余量，避免轻微像素差也触发原图升级。
        return currentLongestEdge + 96 < requiredLongestEdge
    }
}
