import SwiftUI
import AppKit

// ⚠️ 极其核心：自定义窗口子类，打破代码创建窗口的焦点限制
class StandaloneEditWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class EditWindowManager: NSObject, NSWindowDelegate {
    static let shared = EditWindowManager()

    // 记录正在编辑的窗口，防止重复打开 [ItemID: NSWindow]
    private var openWindows: [String: NSWindow] = [:]

    func openEditor(for item: ClipboardItem, viewModel: ClipboardViewModel) {
        let windowId = item.id.uuidString

        // 如果已经打开了，直接拉到最前
        if let existingWindow = openWindows[windowId] {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // 创建独立运行的 SwiftUI 视图
        let editView = StandaloneEditView(item: item, viewModel: viewModel, windowId: windowId)
        let hostingController = NSHostingController(rootView: editView)

        // 创建具有顶级响应者权限的原生窗口
        let window = StandaloneEditWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "编辑文本"
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self

        // 记录并显示
        openWindows[windowId] = window
        window.makeKeyAndOrderFront(nil)
        window.makeMain() // ⚠️ 极其核心：强制成为主窗口，接管 Inspector Bar 的所有格式化动作
        NSApp.activate(ignoringOtherApps: true)
    }

    // ⚠️ 极其核心：拦截窗口关闭事件，对标 PasteNow 的未保存提示
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 查找对应的 Item ID
        guard let windowId = openWindows.first(where: { $1 === sender })?.key else { return true }

        let alert = NSAlert()
        alert.messageText = "您想要保存更改吗？"
        alert.informativeText = "如果不保存，你的更改将会丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        // 使用原生的 Sheet 形式附着在当前窗口上
        alert.beginSheetModal(for: sender) { response in
            switch response {
            case .alertFirstButtonReturn: // 保存
                // 发送保存通知，让 SwiftUI 视图执行保存逻辑
                NotificationCenter.default.post(name: NSNotification.Name("SaveEdit-\(windowId)"), object: nil)
                self.closeAndCleanUp(windowId: windowId, window: sender)
            case .alertSecondButtonReturn: // 不保存
                self.closeAndCleanUp(windowId: windowId, window: sender)
            default: // 取消
                break
            }
        }
        return false // 拦截默认的直接关闭行为
    }

    private func closeAndCleanUp(windowId: String, window: NSWindow) {
        window.delegate = nil
        window.close()
        openWindows.removeValue(forKey: windowId)
    }

    // 供 SwiftUI 内部点击"保存"按钮时主动调用的关闭方法
    func forceClose(windowId: String) {
        if let window = openWindows[windowId] {
            closeAndCleanUp(windowId: windowId, window: window)
        }
    }
}
