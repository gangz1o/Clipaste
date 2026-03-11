import SwiftUI

extension View {
    /// 为任意剪贴板条目附加标准右键菜单。
    /// 传入 nil viewModel 时不挂载 contextMenu，保持向后兼容。
    @ViewBuilder
    func clipboardContextMenu(for item: ClipboardItem, viewModel: ClipboardViewModel?) -> some View {
        if let viewModel {
            self.contextMenu {
            // 1. 核心粘贴操作组
            Button {
                viewModel.pasteToActiveApp(item: item)
            } label: {
                Label("粘贴到当前应用", systemImage: "arrow.turn.down.right")
            }

            Button {
                viewModel.pasteAsPlainText(item: item)
            } label: {
                Label("以纯文本粘贴", systemImage: "doc.plaintext")
            }

            Button {
                viewModel.copyToClipboard(item: item)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Divider()

            // 2. 组织与管理组
            Menu {
                if viewModel.customGroups.isEmpty {
                    Text("暂无自定义分组")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.customGroups) { group in
                        Button {
                            viewModel.assignItemToGroup(item: item, group: group)
                        } label: {
                            Label(group.name, systemImage: group.systemIconName)
                        }
                    }
                }

                Divider()

                Button {
                    print("触发新建分组弹窗")
                } label: {
                    Label("新建分组...", systemImage: "plus")
                }
            } label: {
                Label("添加到分组", systemImage: "folder.badge.plus")
            }

            Button {
                viewModel.pinItem(item: item)
            } label: {
                Label("固定", systemImage: "pin")
            }

            Divider()

            // 3. 编辑组
            Button {
                viewModel.editItemContent(item: item)
            } label: {
                Label("编辑内容", systemImage: "pencil")
            }

            Button {
                viewModel.renameItem(item: item)
            } label: {
                Label("添加标题", systemImage: "character.cursor.ibeam")
            }

            Divider()

            // 4. 预览与分享
            Button {
                viewModel.showPreview(item: item)
            } label: {
                Label("预览", systemImage: "eye")
            }

            Button {
                print("分享")
            } label: {
                Label("分享...", systemImage: "square.and.arrow.up")
            }

            Divider()

            // 5. 破坏性操作（红色警示）
            Button(role: .destructive) {
                viewModel.deleteItem(item: item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        } else {
            self
        }
    }
}
