import SwiftUI
import AppKit

/// 编辑器特权上下文：通信桥梁类。
/// NSTextView 内部的状态绝不实时回传给 SwiftUI，只有点击保存时才通过闭包一次性提取。
class EditorContext {
    var getRTFData: (() -> Data?)?
    var getPlainText: (() -> String)?
    var applyPlainText: (() -> Void)?
}

struct StandaloneEditView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    let windowId: String
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    // ⚠️ 物理隔离：不在 State 中持有 NSAttributedString，仅缓存原始 RTF 数据。
    private let fallbackInitialText: NSAttributedString
    @State private var initialRTFData: Data?
    @State private var didResolveInitialContent = false
    @State private var editorContext = EditorContext()

    init(item: ClipboardItem, viewModel: ClipboardViewModel, windowId: String) {
        self.item = item
        self.viewModel = viewModel
        self.windowId = windowId

        let baseString = item.rawText ?? item.textPreview
        self.fallbackInitialText = NSAttributedString(string: baseString, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ])
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部操作栏 (对标 PasteNow 右上角)
            HStack {
                Spacer()

                Button(action: {
                    // 转换为纯文本：通过上下文闭包在 NSTextView 内部操作，不回传 SwiftUI
                    editorContext.applyPlainText?()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 16))
                        Text(LocalizedStringKey("Use Plain Text"))
                            .editActionLabelStyle()
                    }
                    .frame(width: 104)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: saveAndClose) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                        Text(LocalizedStringKey("Save"))
                            .editActionLabelStyle()
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 富文本编辑器（带原生 Inspector Bar 格式工具栏）
            Group {
                if item.hasRTF, didResolveInitialContent == false {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NativeRichTextEditor(initialText: resolvedInitialText, context: editorContext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task(id: item.id) {
            await loadInitialContentIfNeeded()
        }
        .environment(\.locale, appLanguage.resolvedLocale)
        // 监听来自 WindowManager 的红绿灯拦截保存事件
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SaveEdit-\(windowId)"))) { _ in
            saveData()
        }
    }

    private var resolvedInitialText: NSAttributedString {
        if let initialRTFData,
           let attrString = try? NSAttributedString(
               data: initialRTFData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attrString
        }

        return fallbackInitialText
    }

    private func saveAndClose() {
        saveData()
        EditWindowManager.shared.forceClose(windowId: windowId)
    }

    /// ⚠️ 架构升级：RTF 直接写入 StorageManager，不经过 ViewModel
    private func saveData() {
        let plainText = editorContext.getPlainText?() ?? ""
        let rtfData = editorContext.getRTFData?()

        // 1. ViewModel 仅处理纯文本的乐观 UI 更新
        viewModel.saveEditedItem(item, newText: plainText)

        // 2. RTF 数据直接持久化到数据库（绕过 ViewModel）
        if let rtfData {
            StorageManager.shared.updateRecordText(hash: item.contentHash, newText: plainText, newRTFData: rtfData)
        }

        // 3. 通知渲染引擎清除过期缓存
        ListRenderEngine.shared.invalidate(id: item.id)
    }

    @MainActor
    private func loadInitialContentIfNeeded() async {
        guard didResolveInitialContent == false else { return }

        defer { didResolveInitialContent = true }

        guard item.hasRTF else { return }
        initialRTFData = await StorageManager.shared.loadRTFData(id: item.id)
    }
}

private extension Text {
    func editActionLabelStyle() -> some View {
        self
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }
}
