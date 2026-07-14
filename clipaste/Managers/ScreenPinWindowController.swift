import AppKit
import SwiftUI

@MainActor
final class ScreenPinWindowController: NSObject, NSWindowDelegate {
    let id: UUID

    private let image: NSImage
    private let onClose: (UUID) -> Void
    private let window: ScreenPinPanel
    private var isClosing = false
    private var isRefreshingConstraints = false
    private var interactionPolicy = ScreenPinWindowInteractionPolicy()

    init(
        id: UUID,
        image: NSImage,
        screenPoint: CGPoint,
        initialSizeScale: Double,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.image = image
        self.onClose = onClose

        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let initialSize = ScreenPinGeometry.initialSize(
            imageSize: image.size,
            visibleFrame: visibleFrame,
            scale: initialSizeScale
        )
        let initialFrame = ScreenPinGeometry.droppedFrame(
            size: initialSize,
            topLeftAt: screenPoint,
            visibleFrame: visibleFrame
        )

        self.window = ScreenPinPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow(visibleFrame: visibleFrame)
        let appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .auto
        let rootView = ScreenPinnedImageView(image: image) { [weak self] in
            self?.requestClose()
        }
        .environment(\.locale, appLanguage.resolvedLocale)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setFrame(initialFrame, display: false)
        window.delegate = self
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        guard isClosing == false else { return }
        isClosing = true
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard interactionPolicy.screenDidChange(isLiveResize: window.inLiveResize) else {
            return
        }
        refreshConstraintsForCurrentScreen()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard interactionPolicy.liveResizeDidEnd() else { return }
        refreshConstraintsForCurrentScreen()
    }

    func windowWillClose(_ notification: Notification) {
        guard isClosing == false else { return }
        isClosing = true
        onClose(id)
    }

    private func configureWindow(visibleFrame: CGRect) {
        window.level = .floating
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentAspectRatio = image.size
        applySizeConstraints(visibleFrame: visibleFrame)
    }

    private func requestClose() {
        guard isClosing == false else { return }
        onClose(id)
        close()
    }

    private func refreshConstraintsForCurrentScreen() {
        guard window.inLiveResize == false,
              isRefreshingConstraints == false,
              let screen = window.screen else {
            return
        }
        isRefreshingConstraints = true
        defer { isRefreshingConstraints = false }

        let maximumSize = applySizeConstraints(visibleFrame: screen.visibleFrame)
        guard window.frame.width > maximumSize.width + 0.5
                || window.frame.height > maximumSize.height + 0.5 else {
            return
        }

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let clampedFrame = ScreenPinGeometry.clampedFrame(
            size: maximumSize,
            centeredAt: center,
            visibleFrame: screen.visibleFrame
        )
        if window.frame != clampedFrame {
            window.setFrame(clampedFrame, display: true, animate: false)
        }
    }

    @discardableResult
    private func applySizeConstraints(visibleFrame: CGRect) -> CGSize {
        let maximumSize = ScreenPinGeometry.maximumSize(
            imageSize: image.size,
            visibleFrame: visibleFrame
        )
        window.minSize = ScreenPinGeometry.minimumSize(
            imageSize: image.size,
            maximumSize: maximumSize
        )
        window.maxSize = maximumSize
        return maximumSize
    }
}
