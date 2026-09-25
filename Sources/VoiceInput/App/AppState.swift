import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppState {
    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Lifecycle")
    let settings: AppSettings
    let historyStore: HistoryStore
    let overlayController: OverlayController
    let hotkeyManager: HotkeyManager
    let permissionManager: PermissionManager
    let dictationCoordinator: DictationCoordinator
    let speechModelManager: SpeechModelManager
    let speechRecognizerRouter: SpeechRecognizerRouter

    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = AppSettings()
        let audioLevelMonitor = AudioLevelMonitor()
        let overlayController = OverlayController(
            audioLevelProvider: audioLevelMonitor,
            appearance: settings.overlayAppearance
        )
        let hotkeyManager = HotkeyManager(shortcut: settings.hotkeyShortcut)
        let permissionManager = PermissionManager()
        let historyStore = HistoryStore()
        let speechModelManager = SpeechModelManager()
        let speechRecognizerRouter = SpeechRecognizerRouter(
            mode: settings.speechProcessingMode,
            localRecognizer: speechModelManager,
            apiRecognizer: APISpeechRecognizer()
        )
        let recorder = AudioRecorder(levelMonitor: audioLevelMonitor)
        let dictationCoordinator = DictationCoordinator(
            recorder: recorder,
            speech: speechRecognizerRouter,
            targetCapture: AccessibilityInsertionTargetCapture(),
            textInserter: SystemTextInserter(),
            history: historyStore,
            presenter: overlayController,
            language: { [weak settings] in
                settings?.speechRecognitionLanguage ?? .automatic
            }
        )

        self.settings = settings
        self.historyStore = historyStore
        self.overlayController = overlayController
        self.hotkeyManager = hotkeyManager
        self.permissionManager = permissionManager
        self.dictationCoordinator = dictationCoordinator
        self.speechModelManager = speechModelManager
        self.speechRecognizerRouter = speechRecognizerRouter

        settings.$speechProcessingMode
            .dropFirst()
            .sink { [weak speechRecognizerRouter] mode in
                speechRecognizerRouter?.setMode(mode)
            }
            .store(in: &cancellables)

        settings.$overlayAppearance
            .dropFirst()
            .sink { [weak overlayController] appearance in
                overlayController?.setAppearance(appearance)
            }
            .store(in: &cancellables)

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
        Self.logger.notice(
            "[Lifecycle] permissions Input Monitoring=\(self.permissionManager.hasInputMonitoringPermission, privacy: .public), Accessibility=\(self.permissionManager.hasAccessibilityPermission, privacy: .public), Microphone=\(self.permissionManager.hasMicrophonePermission, privacy: .public)"
        )
        hotkeyManager.updatePermissions(
            inputMonitoring: permissionManager.hasInputMonitoringPermission,
            accessibility: permissionManager.hasAccessibilityPermission
        )
        Self.logger.notice(
            "[Lifecycle] Event Tap=\(self.hotkeyManager.eventTapStatus.diagnosticText, privacy: .public)"
        )
        speechRecognizerRouter.prepare()
    }

    func showSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(
                settings: settings,
                permissionManager: permissionManager,
                hotkeyManager: hotkeyManager,
                speechModelManager: speechModelManager
            )
            settingsWindowController = makeWindowController(
                title: "VoiceInput Settings",
                size: NSSize(width: 540, height: 670),
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
