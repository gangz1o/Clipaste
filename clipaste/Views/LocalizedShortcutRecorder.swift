import KeyboardShortcuts
import SwiftUI

struct LocalizedShortcutRecorder: View {
    @Environment(\.locale) private var locale

    @ObservedObject var viewModel: ShortcutRecorderRowViewModel

    var body: some View {
        ZStack {
            Text(displayText)
                .font(.system(size: 14, weight: viewModel.shortcut == nil ? .regular : .medium))
                .foregroundStyle(viewModel.shortcut == nil ? .secondary : .primary)
                .lineLimit(1)
                .padding(.horizontal, viewModel.shortcut == nil ? 12 : 34)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 140, minHeight: 32)
        .background {
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: viewModel.isRecording ? 2 : 1)
        }
        .overlay(alignment: .trailing) {
            if viewModel.shortcut != nil {
                Button {
                    viewModel.clearShortcutAndRecord()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            viewModel.beginRecording()
        }
        .onDisappear {
            viewModel.cancelRecording()
        }
    }

    private var borderColor: Color {
        if viewModel.isRecording {
            return .accentColor
        }

        return Color(nsColor: .separatorColor)
    }

    private var displayText: String {
        if let shortcut = viewModel.shortcut {
            return shortcut.description
        }

        return placeholderText(isRecording: viewModel.isRecording)
    }

    private func placeholderText(isRecording: Bool) -> String {
        let identifier = locale.identifier(.bcp47).lowercased()

        switch identifier {
        case _ where identifier.hasPrefix("zh-hans"):
            return isRecording ? "按下快捷键" : "设置快捷键"
        case _ where identifier.hasPrefix("zh-hant"):
            return isRecording ? "按下快速鍵" : "設定快速鍵"
        case _ where identifier.hasPrefix("ja"):
            return isRecording ? "キーを押してください" : "キーを記録"
        case _ where identifier.hasPrefix("ko"):
            return isRecording ? "단축키 입력" : "단축키 등록"
        case _ where identifier.hasPrefix("de"):
            return isRecording ? "Kurzbefehl wählen…" : "Kurzbefehl aufnehmen"
        case _ where identifier.hasPrefix("fr"):
            return isRecording ? "Saisir un raccourci" : "Enregistrer le raccourci"
        default:
            return isRecording ? "Press Shortcut" : "Record Shortcut"
        }
    }
}
