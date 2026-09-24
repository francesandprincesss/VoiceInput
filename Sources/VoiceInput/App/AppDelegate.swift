import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let insertionLogger = Logger(
        subsystem: "com.local.voiceinput",
        category: "Insertion"
    )
    private lazy var appState = AppState()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let pasteTestText = pasteTestArgument() {
            runPasteTest(text: pasteTestText)
            return
        }
        configureStatusItem()
        appState.startHotkeyMonitoring()
    }

    private func pasteTestArgument() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--paste-test"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private func runPasteTest(text: String) {
        Self.insertionLogger.notice("[Insertion] TEST begin")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            do {
                let target = try AccessibilityInsertionTargetCapture().capture()
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                Self.insertionLogger.notice("[Insertion] frontmost PID=\(frontmostPID, privacy: .public)")
                Self.insertionLogger.notice("[Insertion] target PID=\(target.processIdentifier, privacy: .public)")
                try await SystemTextInserter().insert(text, into: target)
                Self.insertionLogger.notice("[Insertion] TEST complete")
            } catch {
                Self.insertionLogger.error("[Insertion] TEST failed: \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
