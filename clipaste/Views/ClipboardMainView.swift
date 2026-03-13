import SwiftUI

struct ClipboardMainView: View {
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @FocusState private var isSearchFocused: Bool

    @State private var localEventMonitor: Any?
    @State private var viewRebuildToken: Bool = false

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
        .id(viewRebuildToken)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .background(WindowAppearanceObserver(theme: appTheme))
        .clipShape(RoundedRectangle(cornerRadius: clipboardLayout == .vertical ? 14 : 0))
        .preferredColorScheme(appTheme.colorScheme)
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard notification.object is ClipboardPanel else { return }
            focusSearchField()
        }
        .onChange(of: clipboardLayout) {
            // 1. 先同步通知 PanelManager 瞬间切至目标尺寸
            NotificationCenter.default.post(
                name: .clipboardLayoutModeChanged,
                object: clipboardLayout
            )
            // 2. 下个 run loop 再切换视图 identity，确保 SwiftUI 在新尺寸下重建
            DispatchQueue.main.async {
                viewRebuildToken.toggle()
            }
        }
        .onAppear { setupKeyboardMonitor() }
        .onDisappear {
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

            // ── 空格键 (49) ───────────────────────────────────────────────
            // 规则：有选中项 → 预览优先；否则搜索框正常输入。
            if keyCode == 49 {
                // 输入法候选词未上屏时，绝对放行
                if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.hasMarkedText() {
                    return event
                }
                // 有高亮条目，或正在预览中 → 触发 QuickLook（优先级高于搜索框）
                if viewModel.highlightedItemId != nil || viewModel.quickLookItem != nil {
                    viewModel.toggleQuickLook()
                    return nil
                }
                // 无选中项 → 空格落到搜索框，正常打字
                return event
            }

            // ── 回车键 (36) ───────────────────────────────────────────────
            if keyCode == 36 {
                if viewModel.quickLookItem != nil {
                    viewModel.toggleQuickLook()
                    return nil
                }
                // ⚠️ 搜索框正在输入时，回车放行（如确认输入法候选词）
                if isSearchFocused {
                    return event
                }
                if let hid = viewModel.highlightedItemId,
                   let item = viewModel.filteredItems.first(where: { $0.id == hid }) {
                    viewModel.pasteToActiveApp(item: item)
                } else if let first = viewModel.filteredItems.first {
                    viewModel.pasteToActiveApp(item: first)
                }
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
}
