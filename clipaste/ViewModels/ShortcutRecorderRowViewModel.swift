import AppKit
import Combine
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

nonisolated final class ShortcutRecorderRowViewModel: ObservableObject {
    @Published private(set) var shortcut: KeyboardShortcuts.Shortcut?
    @Published private(set) var isRecording = false

    let name: KeyboardShortcuts.Name

    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private static let shortcutDidChangeNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
    private static let functionKeys: Set<KeyboardShortcuts.Key> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20
    ]

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        self.shortcut = name.shortcut

        NotificationCenter.default.publisher(for: Self.shortcutDidChangeNotification)
            .receive(on: RunLoop.main)
            .compactMap { $0.userInfo?["name"] as? KeyboardShortcuts.Name }
            .filter { [name] changedName in
                changedName == name
            }
            .sink { [weak self] _ in
                self?.shortcut = name.shortcut
            }
            .store(in: &cancellables)
    }

    deinit {
        stopMonitoring()
    }

    var canRestoreDefault: Bool {
        guard let defaultShortcut = name.defaultShortcut else {
            return false
        }

        return shortcut != defaultShortcut
    }

    func restoreDefault() {
        cancelRecording()
        KeyboardShortcuts.reset(name)
        shortcut = name.shortcut
    }

    func beginRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true
        startMonitoring()
    }

    func cancelRecording() {
        guard isRecording else {
            return
        }

        isRecording = false
        stopMonitoring()
    }

    func clearShortcutAndRecord() {
        clearShortcut()
        beginRecording()
    }

    func clearShortcut() {
        name.shortcut = nil
        shortcut = nil
    }

    private func startMonitoring() {
        stopMonitoring()

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleEvent(event) ?? event
        }
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else {
            return event
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            cancelRecording()
            return event
        case .keyDown:
            return handleKeyDown(event)
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = Self.normalizedModifiers(from: event.modifierFlags)

        if modifiers.isEmpty, event.specialKey == .tab {
            cancelRecording()
            return event
        }

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return nil
        }

        if modifiers.isEmpty, Self.isDeleteKey(event) {
            clearShortcut()
            return nil
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event),
              Self.isShortcutAllowed(shortcut: shortcut, modifiers: modifiers) else {
            NSSound.beep()
            return nil
        }

        name.shortcut = shortcut
        self.shortcut = name.shortcut
        cancelRecording()

        return nil
    }

    private static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
    }

    private static func isDeleteKey(_ event: NSEvent) -> Bool {
        event.specialKey == .delete
            || event.specialKey == .deleteForward
            || event.specialKey == .backspace
    }

    private static func isShortcutAllowed(
        shortcut: KeyboardShortcuts.Shortcut,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        !modifiers.subtracting([.shift, .function]).isEmpty
            || (shortcut.key.map { functionKeys.contains($0) } ?? false)
    }
}
