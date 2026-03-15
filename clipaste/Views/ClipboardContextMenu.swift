import SwiftUI

extension View {
    /// Attach context-aware right-click context menu to any clipboard item.
    /// Automatically switches between batch mode (multi-select) and single-item mode.
    @ViewBuilder
    func clipboardContextMenu(for item: ClipboardItem, viewModel: ClipboardViewModel?) -> some View {
        if let viewModel {
            self.contextMenu {
                // ── 状态分流 ──────────────────────────────────────────────
                let isBatchMode = viewModel.selectedItemIDs.contains(item.id)
                    && viewModel.selectedItemIDs.count > 1

                if isBatchMode {
                    // ═══════════════ 分支 A：批量操作菜单 ═══════════════
                    batchMenuContent(viewModel: viewModel)
                } else {
                    // ═══════════════ 分支 B：单项标准菜单 ═══════════════
                    singleItemMenuContent(item: item, viewModel: viewModel)
                }
            }
        } else {
            self
        }
    }

    // MARK: - 批量菜单（View 层仅渲染 + 意图转发）

    @ViewBuilder
    private func batchMenuContent(viewModel: ClipboardViewModel) -> some View {
        let count = viewModel.selectedItemIDs.count

        Button {
            viewModel.batchCopy()
        } label: {
            Label("合并并复制 \(count) 个项目", systemImage: "doc.on.doc")
        }

        Divider()

        Menu {
            if viewModel.customGroups.isEmpty {
                Text("暂无分组")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.customGroups) { group in
                    Button {
                        viewModel.batchAssignToGroup(groupId: group.id)
                    } label: {
                        Label(group.name, systemImage: group.systemIconName)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.batchAssignToGroup(groupId: nil)
            } label: {
                Label("移出分组", systemImage: "folder.badge.minus")
            }
        } label: {
            Label("加入分组", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.batchDelete()
        } label: {
            Label("删除 \(count) 个项目", systemImage: "trash")
        }
    }

    // MARK: - 单项菜单（保持原有功能不变）

    @ViewBuilder
    private func singleItemMenuContent(item: ClipboardItem, viewModel: ClipboardViewModel) -> some View {
        // ⚠️ 商业级 UX 修正：右键未选中卡片时，静默重选该项
        // SwiftUI contextMenu 的 onAppear 时机不可控，因此在菜单 Button action 中处理

        // 1. Core paste actions
        Button {
            viewModel.handleSelection(id: item.id, isCommand: false, isShift: false)
            viewModel.pasteToActiveApp(item: item)
        } label: {
            Label("Paste to Current App", systemImage: "arrow.turn.down.right")
        }

        Button {
            viewModel.handleSelection(id: item.id, isCommand: false, isShift: false)
            viewModel.pasteAsPlainText(item: item)
        } label: {
            Label("Paste as Plain Text", systemImage: "doc.plaintext")
        }

        Button {
            viewModel.handleSelection(id: item.id, isCommand: false, isShift: false)
            viewModel.copyToClipboard(item: item)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Divider()

        // 2. Organize & manage
        Menu {
            if viewModel.customGroups.isEmpty {
                Text("No Custom Groups")
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
                print("trigger new group popover")
            } label: {
                Label("New Group…", systemImage: "plus")
            }
        } label: {
            Label("Add to Group", systemImage: "folder.badge.plus")
        }

        Divider()

        // 3. Edit（上下文感知：按类型分发）
        if item.contentType == .image {
            Button {
                viewModel.editImage(item: item)
            } label: {
                Label("编辑图片", systemImage: "slider.horizontal.3")
            }
        } else {
            Button {
                viewModel.editItemContent(item: item)
            } label: {
                Label("编辑内容", systemImage: "square.and.pencil")
            }
        }

        Button {
            viewModel.renameItem(item: item)
        } label: {
            Label("添加标题", systemImage: "character.cursor.ibeam")
        }

        Divider()

        // 4. Preview & share
        Button {
            viewModel.showPreview(item: item)
        } label: {
            Label("Preview", systemImage: "eye")
        }

        Button {
            viewModel.shareItem(item: item)
        } label: {
            Label("Share…", systemImage: "square.and.arrow.up")
        }

        Divider()

        // 5. Destructive
        Button(role: .destructive) {
            viewModel.deleteItem(item: item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
