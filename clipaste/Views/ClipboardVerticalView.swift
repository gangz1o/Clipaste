import SwiftUI

struct ClipboardVerticalView: View {
    let items: [ClipboardItem]
    var viewModel: ClipboardViewModel
    @AppStorage("singleClickPaste") private var singleClickPaste = false
    @AppStorage("autoPreview") private var autoPreview = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    ClipboardCardView(item: item, viewModel: viewModel)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .help(pasteHelpText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.selectedItemIDs) { _, _ in
            viewModel.scheduleAutoPreviewForSelectionIfNeeded(isEnabled: autoPreview)
        }
        .onChange(of: autoPreview) { _, _ in
            viewModel.presentAutoPreviewForSelectionIfNeeded(isEnabled: autoPreview)
        }
    }

    private var pasteHelpText: Text {
        if singleClickPaste {
            Text("Click to paste to the active app")
        } else {
            Text("Double-click to paste to the active app")
        }
    }
}

#Preview {
    ClipboardVerticalView(items: [], viewModel: ClipboardViewModel())
}
