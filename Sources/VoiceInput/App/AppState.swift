import AppKit
import SwiftUI

@MainActor
final class AppState {
    let settings = AppSettings()
    let historyStore = HistoryStore()
    let overlayController = OverlayController()

    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?

    func showSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(settings: settings)
            settingsWindowController = makeWindowController(
                title: "VoiceInput Settings",
                size: NSSize(width: 420, height: 330),
                rootView: view
            )
        }

        present(settingsWindowController)
    }

    func showHistory() {
        if historyWindowController == nil {
            let view = HistoryView(store: historyStore)
            historyWindowController = makeWindowController(
                title: "History",
                size: NSSize(width: 520, height: 420),
                rootView: view
            )
        }

        present(historyWindowController)
    }

    private func makeWindowController<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.isReleasedWhenClosed = false
        return NSWindowController(window: window)
    }

    private func present(_ controller: NSWindowController?) {
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}
