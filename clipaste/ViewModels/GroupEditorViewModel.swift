import SwiftUI
import Combine

@MainActor
final class GroupEditorViewModel: ObservableObject {
    enum Mode {
        case create
        case edit
    }

    @Published var name: String = ""
    @Published var selectedIconName: String? = nil
    @Published var isIconPickerPresented: Bool = false

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    var title: LocalizedStringResource {
        switch mode {
        case .create:
            return "New Group"
        case .edit:
            return "Edit Group"
        }
    }

    var submitTitle: LocalizedStringResource {
        switch mode {
        case .create:
            return "Create"
        case .edit:
            return "Save"
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        trimmedName.isEmpty == false
    }

    var hasSelectedIcon: Bool {
        selectedIconName != nil
    }

    func prepareForCreate() {
        name = ""
        selectedIconName = nil
        isIconPickerPresented = false
    }

    func prepareForEditing(group: ClipboardGroupItem) {
        name = group.name
        selectedIconName = group.systemIconName
        isIconPickerPresented = false
    }

    func clearIcon() {
        selectedIconName = nil
    }

    func selectIcon(_ iconName: String?) {
        selectedIconName = ClipboardGroupIconName.normalize(iconName)
    }
}
