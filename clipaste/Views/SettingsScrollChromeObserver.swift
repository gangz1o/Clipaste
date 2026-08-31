import AppKit
import SwiftUI


struct SettingsScrollChromeObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.scheduleApply()
    }

    final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleApply()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleApply()
        }

        func scheduleApply() {
            let delays: [TimeInterval] = [0, 0.05, 0.2]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.applyScrollChromeHidden()
                }
            }
        }

        private func applyScrollChromeHidden() {
            guard let rootView = window?.contentView else { return }

            for scrollView in allScrollViews(in: rootView) {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.isHidden = true
                scrollView.horizontalScroller?.isHidden = true
            }
        }

        private func allScrollViews(in rootView: NSView) -> [NSScrollView] {
            var queue: [NSView] = [rootView]
            var scrollViews: [NSScrollView] = []

            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? NSScrollView {
                    scrollViews.append(scrollView)
                }

                queue.append(contentsOf: view.subviews)
            }

            return scrollViews
        }
    }
}

extension View {
    func settingsScrollChromeHidden() -> some View {
        self
            .scrollIndicators(.hidden)
            .background(SettingsScrollChromeObserver())
    }
}
