import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "VoiceInput"
            )
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Settings", action: #selector(openSettings)))
        menu.addItem(menuItem(title: "History", action: #selector(openHistory)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Show Overlay", action: #selector(showOverlay)))
        menu.addItem(menuItem(title: "Hide Overlay", action: #selector(hideOverlay)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quit)))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openSettings() {
        appState.showSettings()
    }

    @objc private func openHistory() {
        appState.showHistory()
    }

    @objc private func showOverlay() {
        appState.overlayController.show()
    }

    @objc private func hideOverlay() {
        appState.overlayController.hide()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
