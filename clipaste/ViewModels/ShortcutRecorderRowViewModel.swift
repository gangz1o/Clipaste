import Combine
import Foundation
import KeyboardShortcuts

@MainActor
final class ShortcutRecorderRowViewModel: ObservableObject {
    @Published private(set) var shortcut: KeyboardShortcuts.Shortcut?

    let name: KeyboardShortcuts.Name

    private var cancellables = Set<AnyCancellable>()
    private static let shortcutDidChangeNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        self.shortcut = name.shortcut

        NotificationCenter.default.publisher(for: Self.shortcutDidChangeNotification)
            .compactMap { $0.userInfo?["name"] as? KeyboardShortcuts.Name }
            .filter { [name] changedName in
                changedName == name
            }
            .sink { [weak self] _ in
                self?.shortcut = name.shortcut
            }
            .store(in: &cancellables)
    }

    var canRestoreDefault: Bool {
        guard let defaultShortcut = name.defaultShortcut else {
            return false
        }

        return shortcut != defaultShortcut
    }

    func restoreDefault() {
        KeyboardShortcuts.reset(name)
        shortcut = name.shortcut
    }
}
