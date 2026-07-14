import AppKit

@MainActor
private final class TestScreenPinImageLoader: ScreenPinImageLoading {
    var image = NSImage(size: CGSize(width: 320, height: 180))
    var delay: Duration?
    private(set) var loadCount = 0
    private(set) var cancelCount = 0

    func screenPinImage(for item: ClipboardItem, maxPixelSize: Int) async -> NSImage? {
        loadCount += 1
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return image
    }

    func cancelScreenPinLoads() {
        cancelCount += 1
    }
}

@MainActor
private final class TestScreenPinWindowCoordinator: ScreenPinWindowCoordinating {
    private(set) var shownPoints: [CGPoint] = []
    private(set) var shownScales: [Double] = []
    private(set) var closeAllCount = 0

    func show(image: NSImage, at screenPoint: CGPoint, initialSizeScale: Double) {
        shownPoints.append(screenPoint)
        shownScales.append(initialSizeScale)
    }

    func closeAll() {
        closeAllCount += 1
    }
}

@main
@MainActor
enum ScreenPinViewModelTests {
    static func main() async {
        let suiteName = "ScreenPinViewModelTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let imageLoader = TestScreenPinImageLoader()
        let coordinator = TestScreenPinWindowCoordinator()
        let viewModel = ScreenPinViewModel(
            defaults: defaults,
            imageLoader: imageLoader,
            windowCoordinator: coordinator
        )

        precondition(viewModel.isEnabled == false, "screen pinning must default to disabled")
        precondition(viewModel.initialSizeScale == 1, "initial size must default to 100 percent")

        viewModel.isEnabled = true
        precondition(defaults.bool(forKey: ScreenPinViewModel.defaultsKey))
        viewModel.initialSizeScale = 0.1
        precondition(viewModel.initialSizeScale == 0.25)
        precondition(
            defaults.double(forKey: ScreenPinViewModel.initialSizeScaleDefaultsKey) == 0.25
        )
        viewModel.initialSizeScale = 0.65
        precondition(
            defaults.double(forKey: ScreenPinViewModel.initialSizeScaleDefaultsKey) == 0.65
        )

        let firstPoint = CGPoint(x: 120, y: 180)
        viewModel.createPin(
            for: ClipboardItem(isScreenPinEligible: true),
            at: firstPoint
        )
        await waitForTasks()
        precondition(coordinator.shownPoints == [firstPoint])
        precondition(coordinator.shownScales == [0.65])

        viewModel.createPin(
            for: ClipboardItem(isScreenPinEligible: false),
            at: CGPoint(x: 240, y: 260)
        )
        await waitForTasks()
        precondition(imageLoader.loadCount == 1, "unsupported items must not start image loading")

        imageLoader.delay = .milliseconds(200)
        viewModel.createPin(
            for: ClipboardItem(isScreenPinEligible: true),
            at: CGPoint(x: 300, y: 320)
        )
        viewModel.isEnabled = false
        try? await Task.sleep(for: .milliseconds(250))

        precondition(coordinator.shownPoints == [firstPoint])
        precondition(coordinator.closeAllCount == 1)
        precondition(imageLoader.cancelCount == 1)
        precondition(defaults.bool(forKey: ScreenPinViewModel.defaultsKey) == false)

        print("ScreenPinViewModelTests passed")
    }

    private static func waitForTasks() async {
        try? await Task.sleep(for: .milliseconds(30))
    }
}
