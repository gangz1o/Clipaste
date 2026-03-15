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

    // ⚠️ 物理隔离：不再使用 @State 持有 NSAttributedString
    let initialText: NSAttributedString
    let context = EditorContext()

    init(item: ClipboardItem, viewModel: ClipboardViewModel, windowId: String) {
        self.item = item
        self.viewModel = viewModel
        self.windowId = windowId

        // ⚠️ 架构升级：从数据库按需加载 RTF，不依赖 DTO 层
        let record = StorageManager.shared.fetchRecord(id: item.id)
        if let rtfData = record?.rtfData,
           let attrString = try? NSAttributedString(
               data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            self.initialText = attrString
        } else {
            let baseString = item.rawText ?? item.textPreview
            self.initialText = NSAttributedString(string: baseString, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部操作栏 (对标 PasteNow 右上角)
            HStack {
                Spacer()

                Button(action: {
                    // 转换为纯文本：通过上下文闭包在 NSTextView 内部操作，不回传 SwiftUI
                    context.applyPlainText?()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 16))
                        Text("使用纯文本")
                            .font(.system(size: 10))
                    }
                    .frame(width: 60)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: saveAndClose) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                        Text("保存")
                            .font(.system(size: 10))
                    }
                    .frame(width: 50)
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
            NativeRichTextEditor(initialText: initialText, context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
        // 监听来自 WindowManager 的红绿灯拦截保存事件
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SaveEdit-\(windowId)"))) { _ in
            saveData()
        }
    }

    private func saveAndClose() {
        saveData()
        EditWindowManager.shared.forceClose(windowId: windowId)
    }

    /// ⚠️ 架构升级：RTF 直接写入 StorageManager，不经过 ViewModel
    private func saveData() {
        let plainText = context.getPlainText?() ?? ""
        let rtfData = context.getRTFData?()

        // 1. ViewModel 仅处理纯文本的乐观 UI 更新
        viewModel.saveEditedItem(item, newText: plainText)

        // 2. RTF 数据直接持久化到数据库（绕过 ViewModel）
        if let rtfData {
            StorageManager.shared.updateRecordText(hash: item.contentHash, newText: plainText, newRTFData: rtfData)
        }

        // 3. 通知渲染引擎清除过期缓存
        ListRenderEngine.shared.invalidate(id: item.id)
    }
}

