import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    var horizontalHybridGroupBar: some View {
        HStack(spacing: 4) {
            allGroupTabButton

            if hasHorizontalScrollableGroupTabs {
                FreeScrollWheelView {
                    scrollableGroupTabsStrip
                }
                .frame(width: horizontalScrollableGroupTabsWidth, alignment: .leading)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            groupOverflowMenu
        }
    }

    // MARK: - 核心组件：单行融合导航栏
    // 固定区域：[全部] … [溢出菜单 ⋯]
    // 可滚动区域：[智能分类…] │ [自定义分组…]
    var allGroupTabButton: some View {
        MinimalGroupTabButton(
            title: .localized(LocalizedStringResource("All")),
            icon: "tray.2.fill",
            isSelected: viewModel.isAllScopeSelected,
            horizontalPadding: groupTabHorizontalPadding,
            verticalPadding: groupTabVerticalPadding,
            iconSpacing: groupTabIconSpacing
        ) {
            selectAllGroup()
        }
    }

    var scrollableGroupTabsStrip: some View {
        HStack(spacing: groupBarSpacing) {
            scrollableGroupTabsContent
        }
        .padding(.horizontal, isVerticalLayout ? 1 : 2)
        .fixedSize(horizontal: true, vertical: false)
        .coordinateSpace(.named(GroupBarDropSpace.name))
        .onPreferenceChange(GroupTabFramePreferenceKey.self) { frames in
            groupTabFrames = frames
        }
        .onDrop(
            of: [ClipboardDragType.group],
            delegate: GroupBarDropDelegate(
                orderedGroupIDs: viewModel.customGroups.map(\.id),
                groupFrames: groupTabFrames,
                reorderTarget: $reorderTarget,
                viewModel: viewModel
            )
        )
    }

    @ViewBuilder
    var scrollableGroupTabsContent: some View {
        ForEach(viewModel.customGroups) { group in
            groupTabButton(group: group)
        }

        if !viewModel.customGroups.isEmpty && !viewModel.visibleBuiltInGroups.isEmpty {
            Divider()
                .frame(height: 16)
                .opacity(0.5)
        }

        ForEach(viewModel.visibleBuiltInGroups, id: \.self) { group in
            builtInGroupTabButton(group)
        }

        if !viewModel.visibleBuiltInGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty {
            Divider()
                .frame(height: 16)
                .opacity(0.5)
        }

        ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
            MinimalGroupTabButton(
                title: .localized(type.localizedFilterTitle),
                icon: type.systemImage,
                isSelected: viewModel.isSmartFilterSelected(type),
                horizontalPadding: groupTabHorizontalPadding,
                verticalPadding: groupTabVerticalPadding,
                iconSpacing: groupTabIconSpacing
            ) {
                selectSmartFilter(type)
            }
        }
    }

    var groupOverflowMenu: some View {
        Button {
            isShowingGroupOverflowPopover = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 24)
        .help("All Groups")
        .popover(isPresented: $isShowingGroupOverflowPopover, arrowEdge: .bottom) {
            groupOverflowPopover
                .environment(\.locale, panelLocale)
        }
        .popover(isPresented: $isShowingNewGroupPopover, arrowEdge: .bottom) {
            newGroupPopover
                .environment(\.locale, panelLocale)
        }
    }

}
