import SwiftUI

/// 右键菜单中带数量的标题，使用 `String Catalog` 中的 `%lld` 占位符并尊重 `\.locale`。
private struct ClipboardCountMenuLabel: View {
    let formatKey: String
    let count: Int
    let systemImage: String

    @Environment(\.locale) private var locale

    var body: some View {
        let format = String(localized: String.LocalizationValue(formatKey), locale: locale)
        let title = String(format: format, locale: locale, count)
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

extension View {
    /// Attach context-aware right-click context menu to any clipboard item.
    /// Automatically switches between batch mode (multi-select) and single-item mode.
    @ViewBuilder
    func clipboardContextMenu(for item: ClipboardItem, viewModel: ClipboardViewModel?) -> some View {
        if let viewModel {
            self.contextMenu {
                let isBatchMode = viewModel.selectedItemIDs.contains(item.id)
                    && viewModel.selectedItemIDs.count > 1

                if isBatchMode {
                    batchMenuContent(viewModel: viewModel)
                } else {
                    singleItemMenuContent(item: item, viewModel: viewModel)
                }
            }
        } else {
            self
        }
    }

    // MARK: - Batch Menu

    @ViewBuilder
    private func batchMenuContent(viewModel: ClipboardViewModel) -> some View {
        let count = viewModel.selectedItemIDs.count
        let selectedItems = viewModel.displayedItemsForInteraction.filter { viewModel.selectedItemIDs.contains($0.id) }
        let hasNonFavoriteItems = selectedItems.contains(where: { $0.isPinned == false })
        let hasFavoriteItems = selectedItems.contains(where: { $0.isPinned })

        Button {
            viewModel.batchCopy()
        } label: {
            ClipboardCountMenuLabel(
                formatKey: "Merge and Copy %lld Items",
                count: count,
                systemImage: "doc.on.doc"
            )
        }

        Divider()

        if hasNonFavoriteItems {
            Button {
                viewModel.addSelectionToFavorites()
            } label: {
                Label("Add to Favorites", systemImage: "star.fill")
            }
        }

        if hasFavoriteItems {
            Button {
                viewModel.removeSelectionFromFavorites()
            } label: {
                Label("Remove from Favorites", systemImage: "star.slash")
            }
        }

        if hasNonFavoriteItems || hasFavoriteItems {
            Divider()
        }

        Menu {
            if viewModel.customGroups.isEmpty {
                Text("No Groups")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.customGroups) { group in
                    Button {
                        viewModel.batchAssignToGroup(groupId: group.id)
                    } label: {
                        GroupMenuLabel(title: group.name, iconName: group.systemIconName)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.batchAssignToGroup(groupId: nil)
            } label: {
                Label("Remove from Group", systemImage: "folder.badge.minus")
            }
        } label: {
            Label("Add to Group", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.batchDelete()
        } label: {
            ClipboardCountMenuLabel(
                formatKey: "Delete %lld Items",
                count: count,
                systemImage: "trash"
            )
        }
    }

    // MARK: - Single Item Menu

    @ViewBuilder
    private func singleItemMenuContent(item: ClipboardItem, viewModel: ClipboardViewModel) -> some View {
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
                        GroupMenuLabel(title: group.name, iconName: group.systemIconName)
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

        Button {
            viewModel.pinItem(item: item)
        } label: {
            Label(
                item.isPinned ? "Remove from Favorites" : "Add to Favorites",
                systemImage: item.isPinned ? "star.slash" : "star.fill"
            )
        }

        Divider()

        // 3. Edit (context-aware: dispatch by type)
        if item.contentType == .image {
            Button {
                viewModel.editImage(item: item)
            } label: {
                Label("Edit Image", systemImage: "slider.horizontal.3")
            }
        } else {
            Button {
                viewModel.editItemContent(item: item)
            } label: {
                Label("Edit Content", systemImage: "square.and.pencil")
            }
        }

        Button {
            viewModel.renameItem(item: item)
        } label: {
            Label("Add Title", systemImage: "character.cursor.ibeam")
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
