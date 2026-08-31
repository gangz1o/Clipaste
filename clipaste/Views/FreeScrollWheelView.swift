import SwiftUI
import UniformTypeIdentifiers


extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - 免 Shift 横向滚动组件

/// 将垂直滚轮事件重定向为横向滚动的轻量级 NSScrollView 包装器。
/// 用于分组导航栏等窄小横向滚动区域，让用户无需按住 Shift 即可横向滚动。
struct FreeScrollWheelView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> _FreeScrollNSScrollView {
        let scrollView = _FreeScrollNSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        // 固定高度跟随容器，宽度自适应内容
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ nsView: _FreeScrollNSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

/// 自定义 NSScrollView：拦截垂直滚轮事件，转换为横向滚动。
/// 同时确保拖拽事件透传到子视图（SwiftUI .onDrop）。
final class _FreeScrollNSScrollView: NSScrollView {

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 注册内部拖拽类型，确保 NSScrollView 不会吞掉拖拽事件
        registerForDraggedTypes([
            .init(ClipboardDragType.item),
            .init(ClipboardDragType.group),
            .string
        ])
    }

    // MARK: - 拖拽透传：全部转发给 documentView (SwiftUI HostingView)
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return documentView?.draggingEntered(sender) ?? super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return documentView?.draggingUpdated(sender) ?? super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        documentView?.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return documentView?.prepareForDragOperation(sender) ?? super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return documentView?.performDragOperation(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        documentView?.concludeDragOperation(sender)
    }

    // MARK: - 滚轮重定向
    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        // 只在垂直分量主导时执行重定向
        guard abs(dy) > abs(dx), dy != 0 else {
            super.scrollWheel(with: event)
            return
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let delta = dy * multiplier

        let clipView = self.contentView
        var origin = clipView.bounds.origin
        origin.x -= delta

        // Clamp
        let documentWidth = self.documentView?.frame.width ?? 0
        let visibleWidth = clipView.bounds.width
        let maxX = max(0, documentWidth - visibleWidth)
        origin.x = max(0, min(origin.x, maxX))

        clipView.scroll(to: NSPoint(x: origin.x, y: clipView.bounds.origin.y))
        reflectScrolledClipView(clipView)
    }
}
