import SwiftUI

struct ClipboardMainView: View {
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @FocusState private var isSearchFocused: Bool

    @State private var localEventMonitor: Any?
    @State private var viewRebuildToken: Bool = false
    private let searchService = TypeToSearchService.shared

    var body: some View {
        Group {
            if clipboardLayout == .horizontal {
                VStack(spacing: 0) {
                    ClipboardHeaderView(viewModel: viewModel, isSearchFocused: _isSearchFocused)
                    mainContent
                }
            } else {
                mainContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ClipboardHeaderView(viewModel: viewModel, isSearchFocused: _isSearchFocused)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack {
                            Text("\(viewModel.filteredItems.count) 个项目")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .padding(.top, 4)
                        .background(.regularMaterial)
                    }
            }
        }
        .id("\(runtimeStore.rootIdentity)-\(viewRebuildToken)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .background(WindowAppearanceObserver(theme: appTheme))
        .clipShape(RoundedRectangle(cornerRadius: clipboardLayout == .vertical ? 14 : 0))
        .preferredColorScheme(appTheme.colorScheme)
        .edgesIgnoringSafeArea(.all)
        .onChange(of: clipboardLayout) {
            NotificationCenter.default.post(
                name: .clipboardLayoutModeChanged,
                object: clipboardLayout
            )
            DispatchQueue.main.async {
                viewRebuildToken.toggle()
            }
        }
        // ── 智能失焦：用户点选卡片后自动将搜索框失焦 ─────────────────
        .onChange(of: viewModel.selectedItemIDs) { _, newValue in
            if !newValue.isEmpty {
                isSearchFocused = false
            }
        }
        // ── 实时同步焦点状态给盲打服务 ─────────────────────────
        .onChange(of: isSearchFocused) { _, newValue in
            searchService.isTextFieldFocused = newValue
        }
        .onAppear {
            setupKeyboardMonitor()
            // 盲打搜索服务挂载（必须在 setupKeyboardMonitor 之后，
            // 确保快捷键监听器优先拦截特殊按键）
            searchService.onCapture = { [weak viewModel] char in
                viewModel?.appendBlindTypedCharacter(char)
            }
            searchService.onRequireFocus = { isSearchFocused = true }
            searchService.start()
        }
        .onDisappear {
            searchService.stop()
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
                localEventMonitor = nil
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.filteredItems.isEmpty {
            ClipboardEmptyStateView(viewModel: viewModel)
        } else {
            switch clipboardLayout {
            case .horizontal:
                ClipboardHorizontalView(
                    items: viewModel.filteredItems,
                    onSelect: { viewModel.userDidSelect(item: $0) },
                    viewModel: viewModel
                )
            case .vertical:
                ClipboardVerticalListView(viewModel: viewModel)
            }
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func setupKeyboardMonitor() {
        if let existing = localEventMonitor { NSEvent.removeMonitor(existing) }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode

            // ── Esc (53) ──────────────────────────────────────────────────
            if keyCode == 53 {
                if viewModel.quickLookItem != nil {
                    viewModel.toggleQuickLook()
                } else if !viewModel.searchInput.isEmpty {
                    viewModel.searchInput = ""
                } else {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("HidePanelForce"), object: nil
                    )
                }
                return nil
            }

            // ── 空格键 (49) ───────────────────────────────────────────
            if keyCode == 49 {
                // 输入法候选词未上屏时，绝对放行
                if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.hasMarkedText() {
                    return event
                }
                // 搜索框已聚焦 → 空格正常输入，不劫持为 QuickLook
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                // 有选中项或正在预览 → QuickLook
                if !viewModel.selectedItemIDs.isEmpty || viewModel.quickLookItem != nil {
                    viewModel.toggleQuickLook()
                    return nil
                }
                return event
            }

            // ── 回车键 (36) ───────────────────────────────────────────────
            if keyCode == 36 {
                if viewModel.quickLookItem != nil {
                    viewModel.toggleQuickLook()
                    return nil
                }
                // ☸️ 核心修复：检查当前第一响应者是否为文本输入控件
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   firstResponder is NSTextView || firstResponder is NSTextField {
                    return event
                }
                if let firstID = viewModel.selectedItemIDs.first,
                   let item = viewModel.filteredItems.first(where: { $0.id == firstID }) {
                    viewModel.pasteToActiveApp(item: item)
                } else if let first = viewModel.filteredItems.first {
                    viewModel.pasteToActiveApp(item: first)
                }
                return nil
            }

            // ── Cmd+F (keyCode 3) ───────────────────────────────────────
            if keyCode == 3, event.modifierFlags.contains(.command) {
                focusSearchField()
                return nil
            }

            // ── Cmd+A (keyCode 0) ───────────────────────────────────────
            if keyCode == 0, event.modifierFlags.contains(.command) {
                // 焦点安全隔离：搜索框内 Cmd+A 执行文本全选，不劫持列表
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                viewModel.selectAll()
                return nil
            }

            // ── 方向键（有无搜索内容均可导航）────────────────────────────
            if viewModel.quickLookItem == nil {
                let isVertical = UserDefaults.standard.bool(forKey: "isVerticalLayout")
                if isVertical {
                    if keyCode == 125 { viewModel.moveSelection(direction: 1);  return nil }
                    if keyCode == 126 { viewModel.moveSelection(direction: -1); return nil }
                } else {
                    if keyCode == 124 { viewModel.moveSelection(direction: 1);  return nil }
                    if keyCode == 123 { viewModel.moveSelection(direction: -1); return nil }
                }
            }

            return event
        }
    }
}

#Preview {
    ClipboardMainView()
        .environmentObject(ClipboardRuntimeStore.shared)
}
