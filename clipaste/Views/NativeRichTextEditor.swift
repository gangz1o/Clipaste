import SwiftUI
import AppKit

/// NSTextView-backed rich text editor with native Inspector Bar (formatting toolbar).
struct NativeRichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // 基础编辑配置
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor.textColor
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // 召唤原生高级检查器栏
        textView.usesInspectorBar = true
        // ⚠️ 极其核心：必须授权使用字体面板，否则 Inspector Bar 的加粗/斜体指令会被 NSTextView 物理丢弃
        textView.usesFontPanel = true
        textView.usesRuler = true // 开启标尺与段落对齐支持

        // 非连续布局：支持大文本
        textView.layoutManager?.allowsNonContiguousLayout = true

        // 初始内容
        textView.textStorage?.setAttributedString(text)

        // ⚠️ 使用 NSTextStorageDelegate 代替 NSTextViewDelegate，
        // 以同时捕获字符变动和属性变动（加粗、颜色等）
        textView.textStorage?.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // 只在外部驱动变化时同步（避免死循环）
        if !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.textStorage?.setAttributedString(text)
            context.coordinator.isUpdating = false
        }
    }

    class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: NativeRichTextEditor
        var isUpdating = false

        init(_ parent: NativeRichTextEditor) {
            self.parent = parent
        }

        // ⚠️ 极其核心：同时监听文本修改和属性修改，避免格式变更被丢弃
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard !isUpdating else { return }
            if editedMask.contains(.editedAttributes) || editedMask.contains(.editedCharacters) {
                DispatchQueue.main.async {
                    self.isUpdating = true
                    self.parent.text = NSAttributedString(attributedString: textStorage)
                    self.isUpdating = false
                }
            }
        }
    }
}
