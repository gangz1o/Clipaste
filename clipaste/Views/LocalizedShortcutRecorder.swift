import KeyboardShortcuts
import SwiftUI

struct LocalizedShortcutRecorder: NSViewRepresentable {
    @Environment(\.locale) private var locale

    let name: KeyboardShortcuts.Name
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(locale: locale)
    }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        context.coordinator.attach(to: recorder)
        context.coordinator.updateLocale(locale)
        return recorder
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        if nsView.shortcutName != name {
            nsView.shortcutName = name
        }

        context.coordinator.updateLocale(locale)
    }

    static func dismantleNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private var locale: Locale
        private weak var recorder: KeyboardShortcuts.RecorderCocoa?
        private var activeObserver: NSObjectProtocol?

        init(locale: Locale) {
            self.locale = locale
        }

        func attach(to recorder: KeyboardShortcuts.RecorderCocoa) {
            self.recorder = recorder

            activeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.schedulePlaceholderRefresh()
            }

            schedulePlaceholderRefresh()
        }

        func detach() {
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
            }

            activeObserver = nil
            recorder = nil
        }

        func updateLocale(_ locale: Locale) {
            self.locale = locale
            schedulePlaceholderRefresh()
        }

        private func schedulePlaceholderRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let recorder = self.recorder else { return }
                recorder.placeholderString = self.placeholderText(isRecording: recorder.currentEditor() != nil)
            }
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
}
