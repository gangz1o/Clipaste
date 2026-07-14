import CoreGraphics

enum ScreenPinRenderPolicy {
    static let minimumPixelSize = 256
    static let maximumPixelSize = 4_096

    static func targetPixelSize(
        pointDimension: CGFloat,
        backingScaleFactor: CGFloat
    ) -> Int {
        guard pointDimension.isFinite,
              backingScaleFactor.isFinite,
              pointDimension > 0,
              backingScaleFactor > 0 else {
            return minimumPixelSize
        }

        let requestedSize = Int(ceil(pointDimension * backingScaleFactor))
        return max(minimumPixelSize, min(requestedSize, maximumPixelSize))
    }
}
