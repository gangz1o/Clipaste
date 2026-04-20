import KeyboardShortcuts
import SwiftUI

struct LocalizedShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self.onChange = onChange
    }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        if nsView.shortcutName != name {
            nsView.shortcutName = name
        }
    }
}
