import SwiftUI

/// 修饰键选择器 — 用于非全局快捷键的修饰键配置（如快速粘贴 ⌘+数字）
struct ModifierPickerView: View {
    let title: LocalizedStringKey
    let suffix: String
    @Binding var selection: ModifierKey
    var excludedOption: ModifierKey?
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Text(title)
            if !suffix.isEmpty {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $selection) {
                ForEach(ModifierKey.allCases) { option in
                    Text(verbatim: option.pickerLabel(locale: locale))
                        .tag(option)
                        .disabled(option == excludedOption)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
