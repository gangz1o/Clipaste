import Combine
import SwiftUI

/// Debounce helper used by `ClipboardVerticalListView` to throttle preview updates
/// triggered by mouse hover events without relying on manual `Timer` management.
private final class HoverDebouncer: ObservableObject {
    private let subject = PassthroughSubject<ClipboardItem, Never>()
    private var cancellable: AnyCancellable?

    var onUpdate: ((ClipboardItem) -> Void)? {
        didSet { rebind() }
    }

    private func rebind() {
        cancellable = subject
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] item in
                self?.onUpdate?(item)
            }
    }

    func send(_ item: ClipboardItem) {
        subject.send(item)
    }
}

struct ClipboardVerticalListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let items: [ClipboardItem]
    @FocusState var focusedField: ClipboardPanelFocusField?
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @AppStorage("previewPanelMode") private var previewPanelMode: PreviewPanelMode = .disabled

    // Preview state - selected item for preview when enabled
    @State private var selectedPreviewItem: ClipboardItem?
    @State private var keyboardSelectedItem: ClipboardItem?
    @StateObject private var hoverDebouncer = HoverDebouncer()
    @State private var isHoveringItem: Bool = false

    // Layout constants
    private let previewAnimationDuration: Double = 0.3

    private var isCompact: Bool {
        clipboardLayout == .compact
    }

    private var isPreviewEnabled: Bool {
        previewPanelMode == .enabled
    }

    private var itemSpacing: CGFloat {
        isCompact ? 2 : 8
    }

    private var horizontalPadding: CGFloat {
        isCompact ? 4 : 12
    }

    private var verticalPadding: CGFloat {
        isCompact ? 6 : 12
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main list content
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Preview panel (always visible when enabled)
            if isPreviewEnabled, let previewItem = selectedPreviewItem {
                ClipboardItemPreviewView(item: previewItem, viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: previewAnimationDuration, dampingFraction: 0.85), value: selectedPreviewItem?.id)
        .onChange(of: viewModel.selectedItemIDs) { oldValue, newValue in
            // Update preview when selection changes via keyboard
            handleSelectionChange()
        }
        .onAppear {
            hoverDebouncer.onUpdate = { item in
                updatePreview(for: item)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: itemSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardVerticalItemView(
                            item: item,
                            viewModel: viewModel,
                            quickPasteIndex: index < 9 ? index : nil,
                            onHoverChange: { isHovering in
                                handleHoverChange(item: item, isHovering: isHovering)
                            }
                        )
                            .id(item.id)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focusedField, equals: .clipList)
            .simultaneousGesture(TapGesture().onEnded {
                focusedField = .clipList
            })
            .onDeleteCommand {
                viewModel.deleteSelection(isCommandHeld: false)
            }
            .onAppear {
                scrollToPrimarySelection(with: proxy, animated: false)
                // Initialize preview with first selected item if preview is enabled
                if isPreviewEnabled {
                    updatePreviewFromKeyboardSelection()
                }
            }
            .onChange(of: viewModel.listScrollRequest) { _, request in
                guard let request else { return }
                scrollToItem(
                    with: proxy,
                    itemID: request.id,
                    animated: request.animated
                )
            }
            .frame(maxHeight: .infinity)
        }
        // 材质由 ClipboardMainView 最外层统一提供，此处不做局部 background
    }

    // MARK: - Preview Management

    private func handleHoverChange(item: ClipboardItem, isHovering: Bool) {
        guard isPreviewEnabled else { return }

        if isHovering {
            // Start hovering — debounce the preview update to avoid flicker
            isHoveringItem = true
            hoverDebouncer.send(item)
        } else {
            // Stop hovering - immediately revert to keyboard selection
            isHoveringItem = false
            updatePreviewFromKeyboardSelection()
        }
    }

    private func handleSelectionChange() {
        guard isPreviewEnabled else { return }
        
        // Update keyboard selection
        if let selectedID = viewModel.selectedItemIDs.first,
           let selectedItem = items.first(where: { $0.id == selectedID }) {
            keyboardSelectedItem = selectedItem
            
            // Only update preview if not hovering
            if !isHoveringItem {
                updatePreviewFromKeyboardSelection()
            }
        }
    }

    private func updatePreview(for item: ClipboardItem) {
        guard isPreviewEnabled else { return }
        guard selectedPreviewItem?.id != item.id else { return }
        withAnimation {
            selectedPreviewItem = item
        }
    }

    private func updatePreviewFromKeyboardSelection() {
        guard isPreviewEnabled else { return }
        
        if let keyboardItem = keyboardSelectedItem {
            updatePreview(for: keyboardItem)
        } else {
            // Fallback to getting from viewModel
            if let selectedID = viewModel.selectedItemIDs.first,
               let selectedItem = items.first(where: { $0.id == selectedID }) {
                updatePreview(for: selectedItem)
            }
        }
    }

    // MARK: - Scroll Management

    private func scrollToPrimarySelection(with proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedID = viewModel.lastSelectedID ?? viewModel.selectedItemIDs.first else { return }
        scrollToItem(with: proxy, itemID: selectedID, animated: animated)
    }

    private func scrollToItem(with proxy: ScrollViewProxy, itemID: UUID, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            } else {
                proxy.scrollTo(itemID, anchor: .center)
            }
        }
    }
}

#Preview {
    ClipboardVerticalListPreview()
}

private struct ClipboardVerticalListPreview: View {
    @FocusState private var focusedField: ClipboardPanelFocusField?

    var body: some View {
        ClipboardVerticalListView(
            viewModel: ClipboardViewModel(),
            items: [],
            focusedField: _focusedField
        )
    }
}
