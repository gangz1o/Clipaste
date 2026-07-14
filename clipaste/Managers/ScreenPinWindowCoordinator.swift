import AppKit

@MainActor
final class ScreenPinWindowCoordinator: ScreenPinWindowCoordinating {
    static let shared = ScreenPinWindowCoordinator()

    private var controllers: [UUID: ScreenPinWindowController] = [:]

    private init() {}

    func show(image: NSImage, at screenPoint: CGPoint, initialSizeScale: Double) {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let id = UUID()
        let controller = ScreenPinWindowController(
            id: id,
            image: image,
            screenPoint: screenPoint,
            initialSizeScale: initialSizeScale
        ) { [weak self] closedID in
            self?.controllers.removeValue(forKey: closedID)
        }
        controllers[id] = controller
        controller.show()
    }

    func closeAll() {
        let activeControllers = Array(controllers.values)
        controllers.removeAll(keepingCapacity: false)
        for controller in activeControllers {
            controller.close()
        }
    }

    func close(id: UUID) {
        guard let controller = controllers.removeValue(forKey: id) else { return }
        controller.close()
    }
}
