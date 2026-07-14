import CoreGraphics

enum ScreenPinGeometry {
    static let screenMargin: CGFloat = 12
    static let minimumLongEdge: CGFloat = 160
    static let preferredInitialLongEdge: CGFloat = 240

    static func initialSize(
        imageSize: CGSize,
        visibleFrame: CGRect,
        scale: CGFloat
    ) -> CGSize {
        let normalizedImageSize = normalized(size: imageSize)
        var candidate = scaled(normalizedImageSize, by: min(max(scale, 0.25), 1))
        let longEdge = max(candidate.width, candidate.height)
        if longEdge < preferredInitialLongEdge {
            candidate = scaled(candidate, by: preferredInitialLongEdge / longEdge)
        }

        return aspectFit(candidate, inside: maximumSize(imageSize: imageSize, visibleFrame: visibleFrame))
    }

    static func minimumSize(imageSize: CGSize, maximumSize: CGSize) -> CGSize {
        let normalizedImageSize = normalized(size: imageSize)
        let longEdge = max(normalizedImageSize.width, normalizedImageSize.height)
        let preferredMinimum = scaled(normalizedImageSize, by: minimumLongEdge / longEdge)
        return aspectFit(preferredMinimum, inside: normalized(size: maximumSize))
    }

    static func maximumSize(imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let availableSize = insetVisibleFrame(visibleFrame).size
        return aspectFit(
            normalized(size: imageSize),
            inside: normalized(size: availableSize),
            allowsUpscaling: true
        )
    }

    static func clampedFrame(
        size: CGSize,
        centeredAt point: CGPoint,
        visibleFrame: CGRect
    ) -> CGRect {
        let availableFrame = insetVisibleFrame(visibleFrame)
        let fittedSize = aspectFit(normalized(size: size), inside: normalized(size: availableFrame.size))
        let proposedOrigin = CGPoint(
            x: point.x - fittedSize.width / 2,
            y: point.y - fittedSize.height / 2
        )
        let clampedOrigin = clampedOrigin(proposedOrigin, size: fittedSize, inside: availableFrame)

        return CGRect(origin: clampedOrigin, size: fittedSize)
    }

    static func droppedFrame(
        size: CGSize,
        topLeftAt point: CGPoint,
        visibleFrame: CGRect
    ) -> CGRect {
        let availableFrame = insetVisibleFrame(visibleFrame)
        let fittedSize = aspectFit(normalized(size: size), inside: normalized(size: availableFrame.size))
        let proposedOrigin = CGPoint(x: point.x, y: point.y - fittedSize.height)
        return CGRect(
            origin: clampedOrigin(proposedOrigin, size: fittedSize, inside: availableFrame),
            size: fittedSize
        )
    }

    private static func insetVisibleFrame(_ visibleFrame: CGRect) -> CGRect {
        let insetFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        guard insetFrame.width > 0, insetFrame.height > 0 else {
            return CGRect(origin: visibleFrame.origin, size: normalized(size: visibleFrame.size))
        }
        return insetFrame
    }

    private static func aspectFit(
        _ size: CGSize,
        inside bounds: CGSize,
        allowsUpscaling: Bool = false
    ) -> CGSize {
        let widthScale = bounds.width / size.width
        let heightScale = bounds.height / size.height
        let maximumScale: CGFloat = allowsUpscaling ? .greatestFiniteMagnitude : 1
        return scaled(size, by: min(widthScale, heightScale, maximumScale))
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        inside frame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }

    private static func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func normalized(size: CGSize) -> CGSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return CGSize(width: preferredInitialLongEdge, height: preferredInitialLongEdge)
        }
        return size
    }
}
