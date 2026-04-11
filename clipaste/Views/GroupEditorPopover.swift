import SwiftUI

struct GroupEditorPopover: View {
    @ObservedObject var viewModel: GroupEditorViewModel
    @Environment(\.locale) private var locale

    let onSubmit: (String, String?) -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                iconPickerButton

                TextField("Group Name", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .tint(.primary)
                    .frame(width: 150)
                    .focused($isNameFocused)
                    .onSubmit { submitIfPossible() }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(viewModel.submitTitle) {
                    submitIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canSubmit == false)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }

    private var iconPickerButton: some View {
        Button {
            viewModel.isIconPickerPresented = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25))
                    )

                if viewModel.hasSelectedIcon {
                    GroupIconView(iconName: viewModel.selectedIconName, size: 17)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Choose Icon")
        .popover(isPresented: $viewModel.isIconPickerPresented) {
            GroupIconPicker(
                selectedIcon: Binding(
                    get: { viewModel.selectedIconName },
                    set: { viewModel.selectIcon($0) }
                )
            )
            .environment(\.locale, locale)
        }
    }

    private func submitIfPossible() {
        guard viewModel.canSubmit else { return }
        onSubmit(viewModel.trimmedName, viewModel.selectedIconName)
    }
}
