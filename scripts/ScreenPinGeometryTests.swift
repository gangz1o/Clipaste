import AppKit

@main
enum ScreenPinGeometryTests {
    static func main() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_000, height: 800)

        assertSize(
            ScreenPinGeometry.initialSize(
                imageSize: CGSize(width: 2_000, height: 1_000),
                visibleFrame: visibleFrame,
                scale: 1
            ),
            equals: CGSize(width: 976, height: 488),
            message: "100 percent uses the original size up to the visible screen limit"
        )

        assertSize(
            ScreenPinGeometry.initialSize(
                imageSize: CGSize(width: 2_000, height: 1_000),
                visibleFrame: visibleFrame,
                scale: 0.25
            ),
            equals: CGSize(width: 500, height: 250),
            message: "initial size applies the configured original-image percentage"
        )

        assertSize(
            ScreenPinGeometry.initialSize(
                imageSize: CGSize(width: 400, height: 200),
                visibleFrame: visibleFrame,
                scale: 1
            ),
            equals: CGSize(width: 400, height: 200),
            message: "images that fit use their original dimensions"
        )

        assertSize(
            ScreenPinGeometry.initialSize(
                imageSize: CGSize(width: 80, height: 40),
                visibleFrame: visibleFrame,
                scale: 1
            ),
            equals: CGSize(width: 240, height: 120),
            message: "small images scale to a usable long edge"
        )

        let maximumSize = ScreenPinGeometry.maximumSize(
            imageSize: CGSize(width: 2_000, height: 1_000),
            visibleFrame: visibleFrame
        )
        assertSize(
            maximumSize,
            equals: CGSize(width: 976, height: 488),
            message: "maximum size respects screen margins and aspect ratio"
        )

        assertSize(
            ScreenPinGeometry.maximumSize(
                imageSize: CGSize(width: 80, height: 40),
                visibleFrame: visibleFrame
            ),
            equals: CGSize(width: 976, height: 488),
            message: "small images can still be enlarged to the screen limit"
        )

        assertSize(
            ScreenPinGeometry.minimumSize(
                imageSize: CGSize(width: 2_000, height: 1_000),
                maximumSize: maximumSize
            ),
            equals: CGSize(width: 160, height: 80),
            message: "minimum size keeps the source aspect ratio"
        )

        let clampedFrame = ScreenPinGeometry.clampedFrame(
            size: CGSize(width: 300, height: 150),
            centeredAt: CGPoint(x: 50, y: 40),
            visibleFrame: visibleFrame
        )
        assertRect(
            clampedFrame,
            equals: CGRect(x: 112, y: 62, width: 300, height: 150),
            message: "drop frames clamp to the visible screen area"
        )

        let oversizedFrame = ScreenPinGeometry.clampedFrame(
            size: CGSize(width: 2_000, height: 1_000),
            centeredAt: CGPoint(x: 600, y: 450),
            visibleFrame: visibleFrame
        )
        assertRect(
            oversizedFrame,
            equals: CGRect(x: 112, y: 206, width: 976, height: 488),
            message: "oversized frames shrink without changing aspect ratio"
        )

        let droppedFrame = ScreenPinGeometry.droppedFrame(
            size: CGSize(width: 300, height: 150),
            topLeftAt: CGPoint(x: 500, y: 600),
            visibleFrame: visibleFrame
        )
        assertRect(
            droppedFrame,
            equals: CGRect(x: 500, y: 450, width: 300, height: 150),
            message: "the pinned image top-left corner matches the mouse release point"
        )

        let edgeDroppedFrame = ScreenPinGeometry.droppedFrame(
            size: CGSize(width: 300, height: 150),
            topLeftAt: CGPoint(x: 1_050, y: 100),
            visibleFrame: visibleFrame
        )
        assertRect(
            edgeDroppedFrame,
            equals: CGRect(x: 788, y: 62, width: 300, height: 150),
            message: "drop positions only shift when required to stay visible"
        )

        precondition(
            ScreenPinRenderPolicy.targetPixelSize(
                pointDimension: 1_440,
                backingScaleFactor: 2
            ) == 2_880,
            "render budget should match the target screen pixel dimension"
        )
        precondition(
            ScreenPinRenderPolicy.targetPixelSize(
                pointDimension: 5_120,
                backingScaleFactor: 2
            ) == 4_096,
            "render budget should cap very large screens at 4096 pixels"
        )
        precondition(
            ScreenPinRenderPolicy.targetPixelSize(
                pointDimension: 80,
                backingScaleFactor: 1
            ) == 256,
            "render budget should keep a useful minimum pixel size"
        )

        print("ScreenPinGeometryTests passed")
    }

    private static func assertSize(
        _ actual: CGSize,
        equals expected: CGSize,
        message: String
    ) {
        assertClose(actual.width, expected.width, message: "\(message) width")
        assertClose(actual.height, expected.height, message: "\(message) height")
    }

    private static func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        message: String
    ) {
        assertClose(actual.minX, expected.minX, message: "\(message) minX")
        assertClose(actual.minY, expected.minY, message: "\(message) minY")
        assertClose(actual.width, expected.width, message: "\(message) width")
        assertClose(actual.height, expected.height, message: "\(message) height")
    }

    private static func assertClose(
        _ actual: CGFloat,
        _ expected: CGFloat,
        message: String
    ) {
        precondition(abs(actual - expected) < 0.001, "\(message): expected \(expected), got \(actual)")
    }
}
