import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    var verticalHeader: some View {
        VStack(spacing: isCompactMode ? 4 : 10) {
            // 第一行：固定按钮 + 搜索框 + 设置菜单
            searchBarContent

            // 第二行：混合分组导航栏（占满全部宽度）- 紧凑模式下隐藏
            if clipboardLayout != .compact {
                hybridGroupBar()
            }
        }
        .padding(.horizontal, isCompactMode ? 4 : 14)
        .padding(.top, isCompactMode ? 4 : 14)
        .padding(.bottom, isCompactMode ? 0 : 2)
    }

    var isCompactMode: Bool {
        clipboardLayout == .compact
    }

    // MARK: - 横版模式：单行紧凑布局
    var horizontalHeader: some View {
        HStack(spacing: 0) {
            horizontalLeadingControls

            Spacer(minLength: 20)

            HStack(spacing: 6) {
                horizontalHybridGroupBar
                    .layoutPriority(1)

                horizontalSearchBar
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    var hasHorizontalScrollableGroupTabs: Bool {
        !viewModel.customGroups.isEmpty || !viewModel.visibleSmartFilters.isEmpty || !viewModel.visibleBuiltInGroups.isEmpty
    }

    var horizontalScrollableGroupTabsWidth: CGFloat {
        let customGroupWidth = CGFloat(viewModel.customGroups.count) * 72
        let smartFilterWidth = CGFloat(viewModel.visibleSmartFilters.count) * 70
        let builtInGroupWidth = CGFloat(viewModel.visibleBuiltInGroups.count) * 76
        let customAndBuiltInDividerWidth: CGFloat =
            (!viewModel.customGroups.isEmpty && !viewModel.visibleBuiltInGroups.isEmpty) ? 14 : 0
        let builtInAndSmartDividerWidth: CGFloat =
            (!viewModel.visibleBuiltInGroups.isEmpty && !viewModel.visibleSmartFilters.isEmpty) ? 14 : 0

        return min(
            680,
            customGroupWidth
                + builtInGroupWidth
                + smartFilterWidth
                + customAndBuiltInDividerWidth
                + builtInAndSmartDividerWidth
        )
    }

    var horizontalLeadingControls: some View {
        HStack(spacing: 0) {
            pinButton
        }
        .frame(width: 28, alignment: .leading)
    }

    var isHorizontalSearchExpanded: Bool {
        focusedField == .searchBar || !viewModel.searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var horizontalSearchBarWidth: CGFloat {
        isHorizontalSearchExpanded
            ? HorizontalSearchLayout.expandedWidth
            : HorizontalSearchLayout.collapsedWidth
    }

    var horizontalSearchContentWidth: CGFloat {
        isHorizontalSearchExpanded
            ? HorizontalSearchLayout.expandedWidth - HorizontalSearchLayout.fieldHeight
            : 0
    }

    var horizontalSearchWidthAnimation: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
    }

    var horizontalSearchContentAnimation: Animation {
        .easeOut(duration: 0.18)
    }

    var horizontalSearchBar: some View {
        HStack(spacing: 0) {
            Button(action: activateHorizontalSearch) {
                horizontalSearchIcon
                    .frame(
                        width: HorizontalSearchLayout.fieldHeight,
                        height: HorizontalSearchLayout.fieldHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: HorizontalSearchLayout.contentSpacing) {
                horizontalSearchTextField
                horizontalSearchClearButton
            }
            .padding(.leading, isHorizontalSearchExpanded ? 4 : 0)
            .padding(.trailing, isHorizontalSearchExpanded ? HorizontalSearchLayout.horizontalPadding : 0)
            .frame(width: horizontalSearchContentWidth, alignment: .leading)
            .opacity(isHorizontalSearchExpanded ? 1 : 0)
            .offset(x: isHorizontalSearchExpanded ? 0 : -4)
            .clipped()
            .allowsHitTesting(isHorizontalSearchExpanded)
            .animation(horizontalSearchContentAnimation, value: isHorizontalSearchExpanded)
        }
        .frame(height: HorizontalSearchLayout.fieldHeight)
        .frame(width: horizontalSearchBarWidth, alignment: .leading)
        .background(Color.clear.background(.regularMaterial))
        .overlay {
            Capsule()
                .strokeBorder(searchFieldFocusColor, lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: searchFieldShadowColor, radius: focusedField == .searchBar ? 8 : 4, y: 2)
        .animation(horizontalSearchWidthAnimation, value: isHorizontalSearchExpanded)
        .animation(.easeInOut(duration: 0.18), value: viewModel.searchInput.isEmpty)
        .help(isHorizontalSearchExpanded ? Text("Search History") : Text("Search"))
    }

    var horizontalSearchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    var horizontalSearchTextField: some View {
        TextField("Search History…", text: searchTextBinding)
            .font(.system(size: 13))
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
#if os(macOS)
            .textContentType(.none)
#endif
            .tint(appAccentColor.color)
            .focused($focusedField, equals: .searchBar)
    }

    @ViewBuilder
    var horizontalSearchClearButton: some View {
        if !viewModel.searchInput.isEmpty {
            Button(action: { viewModel.searchInput = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    func activateHorizontalSearch() {
        withAnimation(horizontalSearchWidthAnimation) {
            focusedField = .searchBar
        }
    }

}
