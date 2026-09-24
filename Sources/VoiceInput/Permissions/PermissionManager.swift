import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import AVFoundation
import CoreGraphics

@MainActor
final class PermissionManager: NSObject, ObservableObject {
    @Published private(set) var hasInputMonitoringPermission = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasMicrophonePermission = false

    var onStatusChange: ((_ inputMonitoring: Bool, _ accessibility: Bool) -> Void)?

    private var pollingTimer: Timer?
    private var isMonitoringSettings = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        refresh()
    }

    func refresh() {
        let inputMonitoring = CGPreflightListenEventAccess()
        let accessibility = AXIsProcessTrusted()
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let changed = inputMonitoring != hasInputMonitoringPermission
            || accessibility != hasAccessibilityPermission

        hasInputMonitoringPermission = inputMonitoring
        hasAccessibilityPermission = accessibility
        hasMicrophonePermission = microphone

        if changed {
            onStatusChange?(inputMonitoring, accessibility)
        }
        updatePollingState()
    }

    func beginSettingsMonitoring() {
        isMonitoringSettings = true
        refresh()
        updatePollingState()
    }

    func endSettingsMonitoring() {
        isMonitoringSettings = false
        stopPolling()
    }

    @discardableResult
    func requestInputMonitoring() -> Bool {
        let granted = CGRequestListenEventAccess()
        refresh()
        updatePollingState()
        return granted || hasInputMonitoringPermission
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refresh()
        updatePollingState()
        return granted || hasAccessibilityPermission
    }

    func requestMicrophone() {
        Task { @MainActor [weak self] in
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            self?.refresh()
            self?.updatePollingState()
        }
    }

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    @objc private func applicationDidBecomeActive() {
        refresh()
    }

    private func updatePollingState() {
        let isMissingPermission = !hasInputMonitoringPermission
            || !hasAccessibilityPermission
            || !hasMicrophonePermission
        if isMonitoringSettings && isMissingPermission {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.75, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
