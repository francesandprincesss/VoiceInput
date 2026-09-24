import AppKit
import SwiftUI

@MainActor
final class AppState {
    let settings: AppSettings
    let historyStore: HistoryStore
    let overlayController: OverlayController
    let hotkeyManager: HotkeyManager
    let permissionManager: PermissionManager
    let dictationCoordinator: DictationCoordinator

    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?

    init() {
        let settings = AppSettings()
        let overlayController = OverlayController()
        let hotkeyManager = HotkeyManager(shortcut: settings.hotkeyShortcut)
        let permissionManager = PermissionManager()
        let dictationCoordinator = DictationCoordinator(overlayController: overlayController)

        self.settings = settings
        historyStore = HistoryStore()
        self.overlayController = overlayController
        self.hotkeyManager = hotkeyManager
        self.permissionManager = permissionManager
        self.dictationCoordinator = dictationCoordinator

        hotkeyManager.onEvent = { [weak settings, weak dictationCoordinator] event in
            guard let settings, let dictationCoordinator else { return }
            dictationCoordinator.handleHotkey(event, mode: settings.hotkeyMode)
        }
        permissionManager.onStatusChange = { [weak hotkeyManager] inputMonitoring, accessibility in
            hotkeyManager?.updatePermissions(
                inputMonitoring: inputMonitoring,
                accessibility: accessibility
            )
        }
        hotkeyManager.updatePermissions(
            inputMonitoring: permissionManager.hasInputMonitoringPermission,
            accessibility: permissionManager.hasAccessibilityPermission
        )
    }

    func startHotkeyMonitoring() {
        permissionManager.refresh()
        hotkeyManager.updatePermissions(
            inputMonitoring: permissionManager.hasInputMonitoringPermission,
            accessibility: permissionManager.hasAccessibilityPermission
        )
    }

    func showSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(
                settings: settings,
                permissionManager: permissionManager,
                hotkeyManager: hotkeyManager,
                dictationCoordinator: dictationCoordinator
            )
            settingsWindowController = makeWindowController(
                title: "VoiceInput Settings",
                size: NSSize(width: 520, height: 650),
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
