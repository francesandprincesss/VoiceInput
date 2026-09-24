import AppKit
import Combine
import CoreGraphics

enum EventTapStatus: Equatable, Sendable {
    case active
    case inactiveMissingInputMonitoring
    case inactiveMissingAccessibility
    case inactiveTapCreationFailed
    case inactiveStopped

    var diagnosticText: String {
        switch self {
        case .active:
            "Active"
        case .inactiveMissingInputMonitoring:
            "Inactive — missing Input Monitoring"
        case .inactiveMissingAccessibility:
            "Inactive — missing Accessibility"
        case .inactiveTapCreationFailed:
            "Inactive — CGEventTapCreate returned nil"
        case .inactiveStopped:
            "Inactive — stopped"
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    @Published private(set) var eventTapStatus: EventTapStatus
    @Published private(set) var boundKeyIsDown = false

    var shortcut: HotkeyShortcut? { matcher.shortcut }
    var eventTapIsActive: Bool { eventTapStatus == .active }

    var onEvent: ((DictationHotkeyEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var matcher: HotkeyMatcher
    private var suspensionCount = 0
    private var hasInputMonitoringPermission = false
    private var hasAccessibilityPermission = false

    init(shortcut: HotkeyShortcut?) {
        matcher = HotkeyMatcher(shortcut: shortcut)
        eventTapStatus = .inactiveMissingInputMonitoring
    }

    func rebind(to shortcut: HotkeyShortcut?) {
        recoverPressedShortcutIfNeeded()
        matcher.rebind(to: shortcut)
        publishPhysicalState()
    }

    func updatePermissions(inputMonitoring: Bool, accessibility: Bool) {
        hasInputMonitoringPermission = inputMonitoring
        hasAccessibilityPermission = accessibility

        guard inputMonitoring else {
            stopTap(status: .inactiveMissingInputMonitoring)
            return
        }
        guard accessibility else {
            stopTap(status: .inactiveMissingAccessibility)
            return
        }
        guard suspensionCount == 0 else { return }
        _ = startIfAuthorized()
    }

    @discardableResult
    private func startIfAuthorized() -> Bool {
        guard hasInputMonitoringPermission else {
            eventTapStatus = .inactiveMissingInputMonitoring
            return false
        }
        guard hasAccessibilityPermission else {
            eventTapStatus = .inactiveMissingAccessibility
            return false
        }
        guard suspensionCount == 0 else { return false }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let isActive = CGEvent.tapIsEnabled(tap: eventTap)
            eventTapStatus = isActive ? .active : .inactiveTapCreationFailed
            return isActive
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                let suppress = MainActor.assumeIsolated {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        manager.handleTapDisabled()
                        return false
                    }
                    return manager.handle(type: type, event: event)
                }
                return suppress ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            eventTapStatus = .inactiveTapCreationFailed
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            eventTapStatus = .inactiveTapCreationFailed
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let isActive = CGEvent.tapIsEnabled(tap: tap)
        eventTapStatus = isActive ? .active : .inactiveTapCreationFailed
        return isActive
    }

    func stop() {
        stopTap(status: .inactiveStopped)
    }

    func suspend() {
        suspensionCount += 1
        if suspensionCount == 1 { stopTapPreservingSuspension() }
    }

    @discardableResult
    func resume() -> Bool {
        suspensionCount = max(0, suspensionCount - 1)
        return suspensionCount == 0 ? startIfAuthorized() : false
    }

    private func stopTapPreservingSuspension() {
        recoverPressedShortcutIfNeeded()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapStatus = .inactiveStopped
        matcher.resetPhysicalState()
        publishPhysicalState()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let inputType: HotkeyInputEventType
        switch type {
        case .keyDown: inputType = .keyDown
        case .keyUp: inputType = .keyUp
        case .flagsChanged: inputType = .flagsChanged
        default: return false
        }
        let physicalKeyIsDown: Bool?
        if PhysicalModifierKey(rawValue: keyCode) != nil {
            physicalKeyIsDown = CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(keyCode)
            )
        } else {
            physicalKeyIsDown = nil
        }
        return process(HotkeyInputEvent(
            type: inputType,
            keyCode: keyCode,
            flags: event.flags,
            isAutoRepeat: type == .keyDown
                && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            physicalKeyIsDown: physicalKeyIsDown
        ))
    }

    /// Processes a normalized event. Kept independent from CGEvent creation so
    /// matching and runtime rebind behavior can be integration-tested.
    @discardableResult
    func process(_ event: HotkeyInputEvent) -> Bool {
        let result = matcher.consume(event)
        publishPhysicalState()
        switch result.action {
        case .pressed:
            onEvent?(.keyDown(isAutoRepeat: false))
        case .released:
            onEvent?(.keyUp)
        case nil:
            break
        }
        return result.suppress
    }

    private func handleTapDisabled() {
        recoverPressedShortcutIfNeeded()
        matcher.resetPhysicalState()
        publishPhysicalState()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            eventTapStatus = CGEvent.tapIsEnabled(tap: eventTap)
                ? .active
                : .inactiveTapCreationFailed
        } else {
            eventTapStatus = .inactiveTapCreationFailed
        }
    }

    private func stopTap(status: EventTapStatus) {
        recoverPressedShortcutIfNeeded()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapStatus = status
        matcher.resetPhysicalState()
        publishPhysicalState()
    }

    private func recoverPressedShortcutIfNeeded() {
        if matcher.isBoundKeyPhysicallyDown {
            onEvent?(.keyUp)
        }
    }

    private func publishPhysicalState() {
        boundKeyIsDown = matcher.isBoundKeyPhysicallyDown
    }
}
