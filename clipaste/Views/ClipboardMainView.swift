import SwiftUI

struct ClipboardMainView: View {
    @StateObject var viewModel = ClipboardViewModel()
    @AppStorage("clipboardLayout") private var clipboardLayout: AppLayoutMode = .horizontal
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)

            // 卡片层 (核心修饰)
            Group {
                switch clipboardLayout {
                case .horizontal:
                    ClipboardHorizontalView(
                        items: viewModel.items,
                        onSelect: { viewModel.userDidSelect(item: $0) }
                    )
                case .vertical:
                    ClipboardVerticalView(
                        items: viewModel.items,
                        onSelect: { viewModel.userDidSelect(item: $0) }
                    )
                }
            }
            .padding(.bottom, 12)
            .safeAreaInset(edge: .top) {
                ClipboardHeaderView(viewModel: viewModel, isSearchFocused: _isSearchFocused)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: focusSearchField)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard notification.object is ClipboardPanel else { return }
            focusSearchField()
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
