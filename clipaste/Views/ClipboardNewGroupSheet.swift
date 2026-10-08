import SwiftUI

/// 右键菜单「新增分组…」的弹窗：创建分组后由调用方把当前记录归入该分组。
struct ClipboardNewGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor = GroupEditorViewModel(mode: .create)

    let onCreate: (String, String?) -> Void

    var body: some View {
        GroupEditorPopover(
            viewModel: editor,
            onCancel: { dismiss() },
            onSubmit: { name, iconName in
                onCreate(name, iconName)
                dismiss()
            }
        )
        .onAppear {
            // 面板的 type-to-search 会拦截按键，弹窗输入期间需要暂停。
            TypeToSearchService.shared.isPaused = true
        }
        .onDisappear {
            TypeToSearchService.shared.isPaused = false
        }
    }
}
