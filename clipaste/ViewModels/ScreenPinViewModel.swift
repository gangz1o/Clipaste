import AppKit
import Foundation
import Observation

@MainActor
protocol ScreenPinWindowCoordinating: AnyObject {
    func show(image: NSImage, at screenPoint: CGPoint, initialSizeScale: Double)
    func closeAll()
}

@MainActor
protocol ScreenPinImageLoading: AnyObject {
    func screenPinImage(for item: ClipboardItem, maxPixelSize: Int) async -> NSImage?
    func cancelScreenPinLoads()
}

extension ClipboardImagePipeline: ScreenPinImageLoading {}

@MainActor
@Observable
final class ScreenPinViewModel {
    static let shared = ScreenPinViewModel()
    static let defaultsKey = "enableScreenPinning"
    static let initialSizeScaleDefaultsKey = "screenPinInitialSizeScale"
    static let minimumInitialSizeScale = 0.25
    static let maximumInitialSizeScale = 1.0
    static let initialSizeScaleStep = 0.05

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled == false {
                closeAll()
            }
        }
    }

    var initialSizeScale: Double {
        didSet {
            let boundedValue = Self.boundedInitialSizeScale(initialSizeScale)
            if boundedValue != initialSizeScale {
                initialSizeScale = boundedValue
            }
            defaults.set(boundedValue, forKey: Self.initialSizeScaleDefaultsKey)
        }
    }

    private(set) var operationNotice: String?

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let imageLoader: ScreenPinImageLoading

    @ObservationIgnored
    private let windowCoordinator: ScreenPinWindowCoordinating

    @ObservationIgnored
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var noticeTask: Task<Void, Never>?

    convenience init(defaults: UserDefaults = .standard) {
        self.init(
            defaults: defaults,
            imageLoader: ClipboardImagePipeline.shared,
            windowCoordinator: ScreenPinWindowCoordinator.shared
        )
    }

    init(
        defaults: UserDefaults,
        imageLoader: ScreenPinImageLoading,
        windowCoordinator: ScreenPinWindowCoordinating
    ) {
        self.defaults = defaults
        self.imageLoader = imageLoader
        self.windowCoordinator = windowCoordinator
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
        if defaults.object(forKey: Self.initialSizeScaleDefaultsKey) == nil {
            self.initialSizeScale = Self.maximumInitialSizeScale
        } else {
            self.initialSizeScale = Self.boundedInitialSizeScale(
                defaults.double(forKey: Self.initialSizeScaleDefaultsKey)
            )
        }
    }

    func createPin(for item: ClipboardItem, at screenPoint: CGPoint) {
        guard isEnabled, item.isScreenPinEligible else { return }

        let requestID = UUID()
        let maxPixelSize = renderPixelSize(for: screenPoint)
        let initialSizeScale = initialSizeScale
        pendingTasks[requestID] = Task { [weak self] in
            guard let self else { return }
            let image = await imageLoader.screenPinImage(for: item, maxPixelSize: maxPixelSize)
            guard Task.isCancelled == false, isEnabled else {
                pendingTasks.removeValue(forKey: requestID)
                return
            }

            pendingTasks.removeValue(forKey: requestID)
            guard let image else {
                showLoadFailureNotice()
                return
            }

            windowCoordinator.show(
                image: image,
                at: screenPoint,
                initialSizeScale: initialSizeScale
            )
        }
    }

    func closeAll() {
        for task in pendingTasks.values {
            task.cancel()
        }
        pendingTasks.removeAll(keepingCapacity: false)
        imageLoader.cancelScreenPinLoads()
        noticeTask?.cancel()
        noticeTask = nil
        operationNotice = nil
        windowCoordinator.closeAll()
    }

    private func renderPixelSize(for screenPoint: CGPoint) -> Int {
        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        guard let screen else { return 2_048 }

        let pointDimension = max(screen.visibleFrame.width, screen.visibleFrame.height)
        return ScreenPinRenderPolicy.targetPixelSize(
            pointDimension: pointDimension,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    private func showLoadFailureNotice() {
        noticeTask?.cancel()
        let language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .auto
        operationNotice = String(
            localized: "Couldn't load the image for screen pinning.",
            locale: language.resolvedLocale
        )

        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard Task.isCancelled == false else { return }
            self?.operationNotice = nil
            self?.noticeTask = nil
        }
    }

    private static func boundedInitialSizeScale(_ value: Double) -> Double {
        min(max(value, minimumInitialSizeScale), maximumInitialSizeScale)
    }
}
