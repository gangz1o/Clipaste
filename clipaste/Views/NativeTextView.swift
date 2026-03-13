import SwiftUI
import AppKit

struct NativeTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // 核心配置：只读、可选中、透明背景
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // 极其关键：开启非连续布局，允许巨量文本在后台分块渲染
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
