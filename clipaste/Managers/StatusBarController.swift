import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settingsMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: ",")
    private let quitMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "q")
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    private var isShowingContextMenu = false

    override init() {
        super.init()
        configureStatusItem()
        configureContextMenu()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        isShowingContextMenu = false
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Clipaste"
        button.setAccessibilityLabel("Clipaste")
    }

    private func configureContextMenu() {
        settingsMenuItem.target = self
        settingsMenuItem.action = #selector(openSettings)
        settingsMenuItem.keyEquivalentModifierMask = [.command]

        quitMenuItem.target = self
        quitMenuItem.action = #selector(quitApp)
        quitMenuItem.keyEquivalentModifierMask = [.command]

        contextMenu.addItem(settingsMenuItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(quitMenuItem)
        refreshMenuTitles()
    }

    private func refreshMenuTitles() {
        let locale = currentAppLocale
        settingsMenuItem.title = String(localized: "Settings…", locale: locale)
        quitMenuItem.title = String(localized: "Quit Clipaste", locale: locale)
    }

    private var currentAppLocale: Locale {
        let appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .auto
        return appLanguage.resolvedLocale
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .leftMouseUp:
            ClipboardPanelManager.shared.showPanel()
        case .rightMouseUp:
            showContextMenu()
        default:
            break
        }
    }

    private func showContextMenu() {
        guard !isShowingContextMenu else { return }

        isShowingContextMenu = true
        refreshMenuTitles()
        ClipboardPanelManager.shared.forceHidePanel()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
    }

    @objc
    private func openSettings() {
        SettingsWindowCoordinator.openFromAppKit()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
