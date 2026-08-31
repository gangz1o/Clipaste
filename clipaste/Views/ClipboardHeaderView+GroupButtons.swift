import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    @ViewBuilder
    func hybridGroupBar() -> some View {
        HStack(spacing: groupBarSpacing) {
            allGroupTabButton

            if hasHorizontalScrollableGroupTabs {
                // “全部”固定在左侧，其余分组在独立滚动区域内横向滚动。
                FreeScrollWheelView {
                    scrollableGroupTabsStrip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            // ── 固定：溢出菜单 ⋯ ─────────────────────────────────
            groupOverflowMenu
        }
    }

    // MARK: - 单个分组 Tab 按钮（支持拖拽 & 右键管理）
    @ViewBuilder
    func builtInGroupTabButton(_ group: ClipboardBuiltInGroup) -> some View {
        let isSelected = viewModel.isBuiltInGroupSelected(group)
        let isDropTarget = targetedBuiltInGroup == group

        MinimalGroupTabButton(
            title: .localized(group.localizedTitle),
            icon: group.systemImage,
            isSelected: isSelected || isDropTarget,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectBuiltInGroup(group)
        }
        .help(Text(group.localizedTitle))
        .onDrop(
            of: [
                ClipboardDragType.item,
                UTType.image.identifier,
                UTType.fileURL.identifier
            ],
            isTargeted: Binding(
                get: { targetedBuiltInGroup == group },
                set: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedBuiltInGroup = isTargeted ? group : nil
                    }
                }
            )
        ) { providers in
            handleItemDrop(providers: providers) { draggedItem in
                viewModel.addItemToBuiltInGroup(item: draggedItem, group: group)
            }
        }
    }

    @ViewBuilder
    func groupTabButton(group: ClipboardGroupItem) -> some View {
        let isSelected = viewModel.isCustomGroupSelected(group.id)
        let isDropTarget = targetedGroupId == group.id
        let insertionEdge = reorderTarget?.groupID == group.id ? reorderTarget?.edge : nil

        MinimalGroupTabButton(
            title: .verbatim(group.name),
            icon: group.systemIconName,
            isSelected: isSelected || isDropTarget,
            maxTextWidth: isVerticalLayout ? 60 : 80,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectCustomGroup(group.id)
        }
        .help(group.name)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: GroupTabFramePreferenceKey.self,
                        value: [group.id: proxy.frame(in: .named(GroupBarDropSpace.name))]
                    )
            }
        )
        .overlay(alignment: .leading) {
            if insertionEdge == .leading {
                groupInsertionIndicator
                    .offset(x: -4)
            }
        }
        .overlay(alignment: .trailing) {
            if insertionEdge == .trailing {
                groupInsertionIndicator
                    .offset(x: 4)
            }
        }
        .onDrag {
            reorderTarget = nil
            viewModel.draggedGroup = group
            let provider = NSItemProvider(object: group.id as NSString)
            provider.registerDataRepresentation(
                forTypeIdentifier: ClipboardDragType.group,
                visibility: .all
            ) { completion in
                completion(group.id.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [
                ClipboardDragType.item,
                UTType.image.identifier,
                UTType.fileURL.identifier
            ],
            isTargeted: Binding(
                get: { targetedGroupId == group.id },
                set: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedGroupId = isTargeted ? group.id : nil
                    }
                }
            )
        ) { providers in
            handleItemDrop(providers: providers) { draggedItem in
                viewModel.assignItemToGroup(item: draggedItem, group: group)
            }
        }
        .contextMenu {
            Button {
                editGroupEditor.prepareForEditing(group: group)
                groupToEdit = group
                showEditPopover = true
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                groupToDelete = group
                showDeleteAlert = true
            } label: { Label("Delete Group", systemImage: "trash") }
        }
    }

    var groupInsertionIndicator: some View {
        Capsule(style: .continuous)
            .fill(appAccentColor.color)
            .frame(width: 3, height: 22)
            .shadow(color: appAccentColor.color.opacity(0.35), radius: 4, y: 1)
            .allowsHitTesting(false)
    }

    // MARK: - 固定面板按钮
}
