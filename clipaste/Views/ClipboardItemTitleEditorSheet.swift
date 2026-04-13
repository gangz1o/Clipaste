import SwiftUI

struct ClipboardItemTitleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let onSave: (String?) -> Void

    @State private var viewModel: ClipboardItemTitleEditorViewModel
    @FocusState private var isTitleFieldFocused: Bool

    init(item: ClipboardItem, onSave: @escaping (String?) -> Void) {
        self.onSave = onSave
        _viewModel = State(initialValue: ClipboardItemTitleEditorViewModel(item: item))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.sheetTitle)
                .font(.title3.weight(.semibold))

            Text(viewModel.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)

            TextField(
                "",
                text: $viewModel.draftTitle,
                prompt: Text("Enter a title")
            )
            .textFieldStyle(.roundedBorder)
            .focused($isTitleFieldFocused)
            .onSubmit(saveAndDismiss)

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Button("Save", action: saveAndDismiss)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.canSave == false)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isTitleFieldFocused = true
        }
    }

    private func saveAndDismiss() {
        let normalizedTitle = viewModel.normalizedTitle
        onSave(normalizedTitle)
        dismiss()
    }
}
