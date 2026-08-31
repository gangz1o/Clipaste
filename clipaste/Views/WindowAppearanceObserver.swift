import AppKit
import SwiftUI


struct WindowAppearanceObserver: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        TrackingView(theme: theme)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        trackingView.update(theme: theme)
    }

    private final class TrackingView: NSView {
        private var theme: AppTheme

        init(theme: AppTheme) {
            self.theme = theme
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTheme()
        }

        func update(theme: AppTheme) {
            self.theme = theme
            applyTheme()
        }

        private func applyTheme() {
            let targetAppearanceName = theme.nsAppearanceName
            let targetAppearance = theme.nsAppearance

            if shouldApplyAppearance(targetAppearanceName, to: window?.appearance) {
                window?.appearance = targetAppearance
            }

            // When reverting to "follow system" (targetAppearance == nil), also reset
            // the app-level appearance so macOS regenerates the effective appearance
            // from the system setting. Guarding this assignment keeps theme changes
            // idempotent, which avoids repeated appearance invalidation loops.
            if shouldApplyAppearance(targetAppearanceName, to: NSApp.appearance) {
                NSApp.appearance = targetAppearance
            }
        }

        private func shouldApplyAppearance(_ targetName: NSAppearance.Name?, to currentAppearance: NSAppearance?) -> Bool {
            if targetName == nil {
                return currentAppearance != nil
            }

            return currentAppearance?.name != targetName
        }
    }
}
