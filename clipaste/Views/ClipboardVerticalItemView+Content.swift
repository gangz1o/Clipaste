import SwiftUI


extension ClipboardVerticalItemView {
    @ViewBuilder
    var rowContent: some View {
        HStack(spacing: isCompact ? 6 : Layout.contentSpacing) {
            // 1. 左侧：App 图标
            AppIconView(appBundleID: item.sourceBundleIdentifier, size: isCompact ? Layout.compactAppIconSize : Layout.appIconSize)
                .shadow(color: Color.black.opacity(0.1), radius: isCompact ? 1 : 2, y: isCompact ? 1 : 1)

            // 2. 中间：内容预览
            VStack(alignment: .leading, spacing: isCompact ? 0 : 4) {
                if item.contentType == .fileURL, let fileURL = item.resolvedFileURL {
                    let displayPath = item.fileDisplayPath ?? fileURL.path

                    if item.fileRepresentsImage {
                        if !isCompact {
                            ClipboardFileThumbnailView(fileURL: fileURL, maxPixelSize: 160) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                            }
                            .frame(maxHeight: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            // Compact: just show file name
                            Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        // ── 文件类型：系统原生图标 + 文件名 + 路径 ──────────────
                        if !isCompact {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: displayPath))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(displayPath)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Compact: just show file name
                            Text(item.fileDisplayName ?? (displayPath as NSString).lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else if item.contentType == .image {
                    if !isCompact {
                        ClipboardThumbnailView(itemID: item.id, maxPixelSize: 160) {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                                .frame(height: 44)
                        }
                        .frame(maxHeight: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // Compact: just show image indicator
                        Text("Image")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    if parsedColor != nil {
                        // 颜色条目：只居中展示等宽色值，背景由卡片层处理
                        Text(previewText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(parsedColor!.isDark ? .white : .black)
                            .shadow(
                                color: parsedColor!.isDark
                                    ? Color.black.opacity(0.3)
                                    : Color.white.opacity(0.3),
                                radius: 1, x: 0, y: 1
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if item.isFastLink {
                        switch viewModel.settingsViewModel.linkDisplayMode {
                        case .rich:
                            ClipboardLinkPreviewRowView(
                                viewModel: ClipboardLinkPreviewViewModel(item: item),
                                highlight: viewModel.activeSearchQuery,
                                isCompact: isCompact
                            )
                        case .plain:
                            ClipboardLinkPlainRowView(
                                viewModel: ClipboardLinkPreviewViewModel(item: item),
                                highlight: viewModel.activeSearchQuery,
                                isCompact: isCompact
                            )
                        }
                    } else {
                        // ⚠️ 渲染核心：ListRenderEngine 缓存优先
                        // 缓存命中 → 0 延迟渲染高亮文本
                        // 缓存未命中 → 瞬间使用纯文本垫底 + onAppear 触发后台缓存
                        if let richPreviewText {
                            Text(richPreviewText)
                                .lineLimit(isCompact ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        } else {
                            HighlightedText(text: previewText, highlight: viewModel.activeSearchQuery)
                                .lineLimit(isCompact ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. 右侧：时间 + 日期双行排版（弱化处理）
            if !isCompact {
                VStack(alignment: .trailing, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(
                            item.timestamp,
                            format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                        )
                            .font(.system(size: 11))
                            .foregroundColor(timeTextColor)

                        Text(item.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.system(size: 9))
                            .foregroundColor(dateTextColor)
                    }

                    Spacer(minLength: 4)

                    bottomInlineAction
                }
                .padding(.top, 4)
                .help(Text(item.timestamp, format: .dateTime.year().month().day().hour().minute()))
                .frame(minWidth: 44, maxHeight: .infinity, alignment: .topTrailing)
            } else {
                // Compact: just show time on the right
                Text(
                    item.timestamp,
                    format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                )
                    .font(.system(size: 10))
                    .foregroundColor(timeTextColor)
                    .help(Text(item.timestamp, format: .dateTime.year().month().day().hour().minute()))
            }
        }
    }

    @ViewBuilder
    var bottomInlineAction: some View {
        if let quickPasteNumber, showsQuickPasteBadge {
            QuickPasteShortcutBadge(
                modifierKey: viewModel.quickPasteModifier,
                number: quickPasteNumber,
                color: timeTextColor
            )
            .transition(.opacity)
        } else if showsInlineActions {
            HStack(spacing: 4) {
                ClipboardFavoriteButton(
                    isFavorite: item.isPinned,
                    accentColor: appAccentColor.color,
                    action: toggleFavorite
                )

                if showsAIShortcut {
                    ClipboardAIActionMenu(item: item, viewModel: viewModel) {
                        ClipboardAIBadgeView(size: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text("AI"))
                }
            }
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    var showsInlineActions: Bool {
        (isHovering || isSelected)
            && viewModel.isQuickPasteModifierHeld == false
    }

    var showsAIShortcut: Bool {
        viewModel.aiSettingsViewModel.isAIEnabled
            && showsInlineActions
    }

    var isScreenPinDragActive: Bool {
        screenPinViewModel.isEnabled && item.isScreenPinEligible
    }

    func toggleFavorite() {
        if singleClickPaste {
            viewModel.handlePrimaryClickSelection(for: item.id)
        }
        viewModel.suppressNextPaste(for: item.id)
        viewModel.pinItem(item: item)
    }

    @ViewBuilder
    var customTitleOverlay: some View {
        if item.hasCustomTitle && !isCompact {
            ClipboardItemCustomTitleView(
                item: item,
                viewModel: viewModel,
                font: .system(size: 11, weight: .semibold),
                textColor: customTitleTextColor
            )
            .frame(
                width: Layout.customTitleWidth,
                height: Layout.customTitleHeight,
                alignment: .topLeading
            )
            .clipped()
            .padding(.leading, Layout.customTitleLeading)
            .padding(.top, Layout.customTitleTop)
        }
    }

    @MainActor
    func refreshRichPreviewText() async {
        richPreviewText = ListRenderEngine.shared.cachedText(for: item.id)

        guard richPreviewText == nil else {
            return
        }

        richPreviewText = await ListRenderEngine.shared.prepareText(for: item)
    }
}
