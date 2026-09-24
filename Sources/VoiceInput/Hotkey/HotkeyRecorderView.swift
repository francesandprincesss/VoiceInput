import AppKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var shortcut: HotkeyShortcut?
    let hotkeyManager: HotkeyManager

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl()
        control.onBeginCapture = { hotkeyManager.suspend() }
        control.onEndCapture = { _ = hotkeyManager.resume() }
        control.onShortcutChange = {
            shortcut = $0
            hotkeyManager.rebind(to: $0)
        }
        control.shortcut = shortcut
        return control
    }

    func updateNSView(_ control: HotkeyRecorderControl, context: Context) {
        if !control.isCapturing {
            control.shortcut = shortcut
        }
    }

    static func dismantleNSView(_ control: HotkeyRecorderControl, coordinator: ()) {
        control.cancelCapture()
    }
}

@MainActor
final class HotkeyRecorderControl: NSButton {
    var shortcut: HotkeyShortcut? {
        didSet { updateTitle() }
    }

    var onBeginCapture: (() -> Void)?
    var onEndCapture: (() -> Void)?
    var onShortcutChange: ((HotkeyShortcut?) -> Void)?
    private(set) var isCapturing = false

    private var oldShortcut: HotkeyShortcut?
    private var activeModifiers: Set<UInt16> = []
    private var capturedModifiers: Set<UInt16> = []
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        target = self
        action = #selector(toggleCapture)
        bezelStyle = .rounded
        alignment = .center
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        setButtonType(.momentaryPushIn)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func toggleCapture() {
        isCapturing ? cancelCapture() : beginCapture()
    }

    private func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        oldShortcut = shortcut
        activeModifiers.removeAll()
        capturedModifiers.removeAll()
        title = "Press a key…"
        onBeginCapture?()
        window?.makeFirstResponder(self)

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self, self.isCapturing else { return event }
            self.consume(event)
            return nil
        }

        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelCapture() }
            }
        }
    }

    private func consume(_ event: NSEvent) {
        let keyCode = UInt16(event.keyCode)

        if event.type == .flagsChanged,
           let modifier = PhysicalModifierKey(rawValue: keyCode) {
            updateModifier(modifier, event: event)
            capturedModifiers.formUnion(activeModifiers)
            if !capturedModifiers.isEmpty {
                title = HotkeyShortcut(modifierKeyCodes: capturedModifiers).displayName
            }
            if activeModifiers.isEmpty, !capturedModifiers.isEmpty {
                commit(HotkeyShortcut(modifierKeyCodes: capturedModifiers))
            }
            return
        }

        guard event.type == .keyDown, !event.isARepeat else { return }

        if keyCode == 53, activeModifiers.isEmpty {
            cancelCapture()
            return
        }

        if (keyCode == 51 || keyCode == 117), activeModifiers.isEmpty {
            commit(nil)
            return
        }

        commit(HotkeyShortcut(keyCode: keyCode, modifierKeyCodes: activeModifiers))
    }

    private func updateModifier(_ modifier: PhysicalModifierKey, event: NSEvent) {
        let isPhysicallyDown = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(modifier.rawValue)
        )
        let familyFlagIsSet = event.modifierFlags.contains(modifier.appKitFlag)
        let wasDown = activeModifiers.contains(modifier.rawValue)
        if !wasDown, familyFlagIsSet {
            activeModifiers.insert(modifier.rawValue)
        } else if wasDown, (!familyFlagIsSet || !isPhysicallyDown) {
            activeModifiers.remove(modifier.rawValue)
        }
    }

    private func commit(_ newShortcut: HotkeyShortcut?) {
        shortcut = newShortcut
        onShortcutChange?(newShortcut)
        endCapture()
    }

    func cancelCapture() {
        guard isCapturing else { return }
        shortcut = oldShortcut
        endCapture()
    }

    private func endCapture() {
        guard isCapturing else { return }
        isCapturing = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        activeModifiers.removeAll()
        capturedModifiers.removeAll()
        updateTitle()
        onEndCapture?()
    }

    private func updateTitle() {
        title = shortcut?.displayName ?? "Not set"
        toolTip = "Click, then press a key or shortcut. Escape cancels; Delete clears."
    }
}
