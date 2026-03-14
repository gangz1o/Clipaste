import SwiftUI

struct StandaloneEditView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardViewModel
    let windowId: String

    // 富文本编辑状态
    @State private var richText: NSAttributedString

    init(item: ClipboardItem, viewModel: ClipboardViewModel, windowId: String) {
        self.item = item
        self.viewModel = viewModel
        self.windowId = windowId

        // 初始化富文本：优先从 rawText 构建
        let baseString = item.rawText ?? item.textPreview
        let attrString = NSAttributedString(string: baseString, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ])
        _richText = State(initialValue: attrString)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部操作栏 (对标 PasteNow 右上角)
            HStack {
                Spacer()

                Button(action: {
                    // 转换为纯文本：剥离所有样式
                    let plainString = richText.string
                    richText = NSAttributedString(string: plainString, attributes: [
                        .font: NSFont.systemFont(ofSize: 14),
                        .foregroundColor: NSColor.textColor
                    ])
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
            NativeRichTextEditor(text: $richText)
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

    private func saveData() {
        let plainText = richText.string
        viewModel.saveEditedItem(item, newText: plainText)
    }
}
