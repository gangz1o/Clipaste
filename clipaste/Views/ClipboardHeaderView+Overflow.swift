import SwiftUI
import UniformTypeIdentifiers


extension ClipboardHeaderView {
    var groupOverflowPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            GroupOverflowSectionTitle("Built-in Groups")

            GroupOverflowRow(
                title: .localized(LocalizedStringResource("All")),
                icon: "tray.2.fill",
                isSelected: viewModel.isAllScopeSelected,
                accentColor: appAccentColor
            ) {
                performGroupOverflowAction(selectAllGroup)
            }

            if !viewModel.customGroups.isEmpty {
                Divider()
                    .padding(.vertical, 3)

                GroupOverflowSectionTitle("Groups")

                ForEach(viewModel.customGroups) { group in
                    GroupOverflowRow(
                        title: .verbatim(group.name),
                        icon: group.systemIconName,
                        isSelected: viewModel.isCustomGroupSelected(group.id),
                        accentColor: appAccentColor
                    ) {
                        performGroupOverflowAction {
                            selectCustomGroup(group.id)
                        }
                    }
                }
            }

            ForEach(viewModel.visibleBuiltInGroups, id: \.self) { group in
                GroupOverflowRow(
                    title: .localized(group.localizedTitle),
                    icon: group.systemImage,
                    isSelected: viewModel.isBuiltInGroupSelected(group),
                    accentColor: appAccentColor
                ) {
                    performGroupOverflowAction {
                        selectBuiltInGroup(group)
                    }
                }
            }

            ForEach(viewModel.visibleSmartFilters, id: \.self) { type in
                GroupOverflowRow(
                    title: .localized(type.localizedFilterTitle),
                    icon: type.systemImage,
                    isSelected: viewModel.isSmartFilterSelected(type),
                    accentColor: appAccentColor
                ) {
                    performGroupOverflowAction {
                        selectSmartFilter(type)
                    }
                }
            }

            if aiSettingsViewModel.isAIEnabled {
                Divider()
                    .padding(.vertical, 3)

                aiModelSubmenu
            }

            Divider()
                .padding(.vertical, 3)

            GroupOverflowRow(
                title: .localized(LocalizedStringResource("New Group…")),
                icon: "plus",
                isSelected: false,
                accentColor: appAccentColor
            ) {
                isShowingGroupOverflowPopover = false
                newGroupEditor.prepareForCreate()
                DispatchQueue.main.async {
                    isShowingNewGroupPopover = true
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 164)
    }

    var aiModelSubmenu: some View {
        Button {
            isShowingAIModelPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 14, height: 14)

                (Text(verbatim: "AI") + Text(" ") + Text(LocalizedStringKey("Model")))
                    .font(.system(size: 14))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isAIModelSubmenuHighlighted ? appAccentColor.selectedContentColor : Color.secondary)
            }
            .foregroundStyle(isAIModelSubmenuHighlighted ? appAccentColor.selectedContentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isAIModelSubmenuHighlighted ? appAccentColor.color : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isAIModelSubmenuHovered = hovering
        }
        .popover(isPresented: $isShowingAIModelPopover, arrowEdge: .trailing) {
            aiModelPopover
                .environment(\.locale, panelLocale)
        }
    }

    var isAIModelSubmenuHighlighted: Bool {
        isAIModelSubmenuHovered || isShowingAIModelPopover
    }

    var aiModelPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            if aiSettingsViewModel.configurations.isEmpty {
                GroupOverflowRow(
                    title: .localized(LocalizedStringResource("Open AI Settings…")),
                    icon: "gearshape",
                    isSelected: false,
                    accentColor: appAccentColor
                ) {
                    isShowingAIModelPopover = false
                    isShowingGroupOverflowPopover = false
                    NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(aiSettingsViewModel.configurations) { config in
                            AIModelOverflowRow(
                                configuration: config,
                                isSelected: aiSettingsViewModel.activeConfigurationID == config.id,
                                accentColor: appAccentColor
                            ) {
                                aiSettingsViewModel.setActive(config)
                                isShowingAIModelPopover = false
                                isShowingGroupOverflowPopover = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 220)
    }

    func performGroupOverflowAction(_ action: () -> Void) {
        action()
        isShowingGroupOverflowPopover = false
    }

}
