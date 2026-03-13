import SwiftUI

/// 修饰键选择器 — 用于非全局快捷键的修饰键配置（如快速粘贴 ⌘+数字）
struct ModifierPickerView: View {
    let title: String
    let suffix: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack {
            Text(title)
            if !suffix.isEmpty {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
