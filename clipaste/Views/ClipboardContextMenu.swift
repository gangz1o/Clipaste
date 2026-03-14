import SwiftUI

extension View {
    /// Attach standard right-click context menu to any clipboard item.
    @ViewBuilder
    func clipboardContextMenu(for item: ClipboardItem, viewModel: ClipboardViewModel?) -> some View {
        if let viewModel {
            self.contextMenu {
                // 1. Core paste actions
                Button {
                    viewModel.pasteToActiveApp(item: item)
                } label: {
                    Label("Paste to Current App", systemImage: "arrow.turn.down.right")
                }

                Button {
                    viewModel.pasteAsPlainText(item: item)
                } label: {
                    Label("Paste as Plain Text", systemImage: "doc.plaintext")
                }

                Button {
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

                // 3. Edit
                Button {
                    viewModel.editItemContent(item: item)
                } label: {
                    Label("Edit Content", systemImage: "pencil")
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
        } else {
            self
        }
    }
}
