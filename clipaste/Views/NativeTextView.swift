import SwiftUI
import AppKit

struct NativeTextView: NSViewRepresentable {
    enum Style {
        case plain
        case code
    }

    var text: String
    var attributedText: NSAttributedString?
    var style: Style = .plain

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // 核心配置：只读、可选中
        textView.isEditable = false
        textView.isSelectable = true

        // 极其关键：开启非连续布局，允许巨量文本在后台分块渲染
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        configureTextView(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        configureTextView(textView)
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.textContainerInset = NSSize(
            width: style == .code ? 16 : 20,
            height: style == .code ? 14 : 20
        )

        if let attrText = attributedText {
            textView.textStorage?.setAttributedString(attrText)
            applyBackgroundStyle(to: textView)
        } else {
            // 纯文本降级模式
            textView.font = .systemFont(ofSize: 14, weight: .regular)
            textView.textColor = NSColor.labelColor
            textView.string = text
            applyBackgroundStyle(to: textView)
        }
    }

    private func applyBackgroundStyle(to textView: NSTextView) {
        guard style == .code else {
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            return
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textView.drawsBackground = true
        textView.backgroundColor = isDark
            ? NSColor(red: 0.17, green: 0.18, blue: 0.23, alpha: 1.0)
            : NSColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
    }
}
