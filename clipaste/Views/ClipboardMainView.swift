import SwiftUI

struct ClipboardMainView: View {
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.openSettings) private var openSettings
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @FocusState private var focusedField: ClipboardPanelFocusField?

    @State private var viewRebuildToken: Bool = false
    private let searchService = TypeToSearchService.shared

    var body: some View {
        configuredContent
    }

    @ViewBuilder
    private var panelLayoutContent: some View {
        Group {
            if clipboardLayout == .horizontal {
                VStack(spacing: 0) {
                    ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    mainContent
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isShowingFreeTierHistoryPreview {
                        historyPreviewFooter
                    }
                }
            } else {
                mainContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ClipboardHeaderView(viewModel: viewModel, focusedField: _focusedField)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        historyPreviewFooter
                    }
            }
        }
    }

    private var showPanelPaywall: Bool {
        storeManager.shouldShowPaywall && storeManager.paywallSource == .panel
    }

    private var configuredContent: some View {
        panelLayoutContent
            .overlay {
                if showPanelPaywall {
                    panelPaywallOverlay
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showPanelPaywall)
            .id("\(runtimeStore.rootIdentity)-\(viewRebuildToken)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
            .background(
                ClipboardPanelWindowObserver(
                    onWindowDidBecomeKey: activatePanelInputHandling,
                    onWindowDidResignKey: deactivatePanelInputHandling
                )
            )
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
                scheduleDefaultListFocus()
            }
            .onChange(of: focusedField) { _, newValue in
                searchService.isTextFieldFocused = (newValue == .searchBar)
            }
            .onChange(of: displayedItemIDs) { _, _ in
                if focusedField == .clipList {
                    viewModel.ensureListSelection()
                }
            }
            .onAppear {
                searchService.onInterceptedKey = { [weak viewModel] char in
                    guard let viewModel else { return false }

                    let shouldEnterSearch = viewModel.handleGlobalKeyPress(char)
                    if shouldEnterSearch {
                        focusSearchField()
                    }

                    return shouldEnterSearch
                }
                syncAccessState()
                scheduleDefaultListFocus()
            }
            .onDisappear {
                searchService.onInterceptedKey = nil
                deactivatePanelInputHandling()
            }
            .onChange(of: storeManager.isTrialExpired) { _, _ in
                syncAccessState()
            }
            .onChange(of: storeManager.isProUnlocked) { _, _ in
                syncAccessState()
            }
            // ── ⌘, 意图通知 → 调用 SwiftUI 原生 openSettings ───────────
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsIntent)) { _ in
                SettingsWindowCoordinator.open {
                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearchFieldIntent)) { _ in
                requestSearchFocus()
            }
    }

    private var panelPaywallOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            SubscriptionModalView(onClose: {
                storeManager.dismissPaywall()
            })
            .environmentObject(storeManager)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private var mainContent: some View {
        if displayedItems.isEmpty {
            ClipboardEmptyStateView(viewModel: viewModel)
        } else {
            switch clipboardLayout {
            case .horizontal:
                ClipboardHorizontalView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: _focusedField
                )
            case .vertical:
                ClipboardVerticalListView(
                    viewModel: viewModel,
                    items: displayedItems,
                    focusedField: _focusedField
                )
            }
        }
    }

    private func focusSearchField() {
        focusedField = .searchBar
    }

    private func requestSearchFocus() {
        guard storeManager.requestAccess(to: .globalSearch, from: .panel) else {
            return
        }

        focusSearchField()
    }

    private func activatePanelInputHandling() {
        viewModel.startKeyboardMonitoring()
        // 先启动面板级键盘监听，再启动盲打搜索，确保特殊按键优先被 ViewModel 消费。
        searchService.start()
        searchService.isTextFieldFocused = (focusedField == .searchBar)
        scheduleDefaultListFocus()
    }

    private func deactivatePanelInputHandling() {
        searchService.stop()
        viewModel.stopKeyboardMonitoring()
    }

    private func syncAccessState() {
        viewModel.updateDisplayedHistoryLimit(storeManager.historyLimitForFreeTier)
        viewModel.handleAccessRestrictionChange(isRestricted: !storeManager.hasFullAccess)
    }

    private func scheduleDefaultListFocus() {
        focusedField = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard NSApp.keyWindow != nil else { return }
            guard focusedField != .searchBar else { return }
            focusedField = .clipList
            viewModel.selectFirstDisplayedItem()
        }
    }

    private var displayedItems: [ClipboardItem] {
        if let historyLimit = storeManager.historyLimitForFreeTier {
            return Array(viewModel.filteredItems.prefix(historyLimit))
        }

        return viewModel.filteredItems
    }

    private var displayedItemIDs: [UUID] {
        displayedItems.map(\.id)
    }

    private var isShowingFreeTierHistoryPreview: Bool {
        (storeManager.historyLimitForFreeTier != nil) && (viewModel.filteredItems.count > displayedItems.count)
    }

    @ViewBuilder
    private var historyPreviewFooter: some View {
        HStack {
            if isShowingFreeTierHistoryPreview {
                Text("Free plan shows latest 10 records only")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("\(displayedItems.count) Items")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isShowingFreeTierHistoryPreview {
                Button(String(localized: "Unlock Pro")) {
                    storeManager.presentPaywall(from: .panel, highlighting: .unlimitedHistory)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .padding(.top, 4)
        .background(.regularMaterial)
    }
}

#Preview {
    ClipboardMainView()
        .environmentObject(AppPreferencesStore.shared)
        .environmentObject(ClipboardRuntimeStore.shared)
        .environmentObject(StoreManager.shared)
}
