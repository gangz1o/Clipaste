import SwiftUI

struct ClipboardMainView: View {
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ClipboardHeaderView(viewModel: viewModel, isSearchFocused: _isSearchFocused)

            // 内容区
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, 12)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard notification.object is ClipboardPanel else { return }
            focusSearchField()
        }
        .onChange(of: clipboardLayout) {
            NotificationCenter.default.post(
                name: .clipboardLayoutModeChanged,
                object: clipboardLayout
            )
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }
}

#Preview {
    ClipboardMainView()
}
