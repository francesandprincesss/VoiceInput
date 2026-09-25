import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import OSLog

enum TextInsertionError: LocalizedError, Equatable {
    case targetApplicationUnavailable
    case targetActivationFailed
    case secureField
    case emptyTranscript
    case clipboardWriteFailed
    case clipboardVerificationFailed
    case accessibilityPermissionMissing
    case pasteEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .targetApplicationUnavailable: "The original application is no longer running."
        case .targetActivationFailed: "The original application could not be activated."
        case .secureField: "VoiceInput will not insert text into a secure field."
        case .emptyTranscript: "The transcript is empty."
        case .clipboardWriteFailed: "The transcription could not be placed on the clipboard."
        case .clipboardVerificationFailed: "The transcription could not be verified on the clipboard."
        case .accessibilityPermissionMissing: "Accessibility permission is required to send the paste shortcut."
        case .pasteEventCreationFailed: "The Cmd+V event could not be created."
        }
    }
}

@MainActor
protocol TextInserting: AnyObject {
    func insert(_ text: String, into target: InsertionTarget) async throws
}

enum AXTextInsertionResult: Equatable {
    case succeeded
    case unsupported(String)
    case failed(AXError, operation: String)
}

enum AXFocusRestorationResult: Equatable {
    case succeeded
    case unavailable(String)
    case failed(AXError, operation: String)
}

@MainActor
protocol AccessibilityTextInserting: AnyObject {
    func insert(_ text: String, into target: InsertionTarget) throws -> AXTextInsertionResult
    func restoreFocus(to target: InsertionTarget) -> AXFocusRestorationResult
}

@MainActor
final class SystemAccessibilityTextInserter: AccessibilityTextInserting {
    func insert(_ text: String, into target: InsertionTarget) throws -> AXTextInsertionResult {
        guard let element = target.focusedElement else {
            return .unsupported("No focused AX element was captured")
        }
        if target.subrole == (kAXSecureTextFieldSubrole as String)
            || stringAttribute(kAXSubroleAttribute as CFString, element: element)
                == (kAXSecureTextFieldSubrole as String) {
            throw TextInsertionError.secureField
        }

        var enabledValue: CFTypeRef?
        let enabledError = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledValue
        )
        if enabledError == .success, let enabled = enabledValue as? Bool, !enabled {
            return .unsupported("Focused AX element is disabled")
        }
        if enabledError != .success && enabledError != .noValue && enabledError != .attributeUnsupported {
            return .failed(enabledError, operation: "read AXEnabled")
        }

        var names: CFArray?
        let namesError = AXUIElementCopyAttributeNames(element, &names)
        guard namesError == .success else {
            return .failed(namesError, operation: "list AX attributes")
        }
        let attributes = (names as? [String]) ?? []
        guard attributes.contains(kAXSelectedTextAttribute as String) else {
            return .unsupported("AXSelectedText is not supported by role \(target.role ?? "unknown")")
        }

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableError == .success else {
            return .failed(settableError, operation: "check AXSelectedText settable")
        }
        guard settable.boolValue else {
            return .unsupported("AXSelectedText is read-only")
        }

        let setError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard setError == .success else {
            return .failed(setError, operation: "set AXSelectedText")
        }
        return .succeeded
    }

    func restoreFocus(to target: InsertionTarget) -> AXFocusRestorationResult {
        guard let element = target.focusedElement else {
            return .unavailable("No focused AX element was captured")
        }
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            element,
            kAXFocusedAttribute as CFString,
            &settable
        )
        guard settableError == .success else {
            return .failed(settableError, operation: "check AXFocused settable")
        }
        guard settable.boolValue else {
            return .unavailable("AXFocused is read-only")
        }
        let setError = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard setError == .success else {
            return .failed(setError, operation: "set AXFocused")
        }
        return .succeeded
    }

    private func stringAttribute(_ attribute: CFString, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}

@MainActor
protocol TargetApplicationActivating: AnyObject {
    func isApplicationAvailable(processIdentifier: pid_t) -> Bool
    func isFrontmost(processIdentifier: pid_t) -> Bool
    func activate(processIdentifier: pid_t, timeout: Duration) async -> Bool
}

@MainActor
final class SystemTargetApplicationActivator: TargetApplicationActivating {
    func isApplicationAvailable(processIdentifier: pid_t) -> Bool {
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return false
        }
        return !application.isTerminated
    }

    func isFrontmost(processIdentifier: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
    }

    func activate(processIdentifier: pid_t, timeout: Duration) async -> Bool {
        guard isApplicationAvailable(processIdentifier: processIdentifier),
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated else { return false }

        application.activate()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if isFrontmost(processIdentifier: processIdentifier) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return isFrontmost(processIdentifier: processIdentifier)
    }
}

@MainActor
protocol PasteEventPosting: AnyObject {
    func postPaste(to processIdentifier: pid_t) async -> Bool
}

@MainActor
final class CGPasteEventPoster: PasteEventPosting {
    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Insertion")

    func postPaste(to _: pid_t) async -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        VoiceInputSyntheticEvent.mark(vDown)
        VoiceInputSyntheticEvent.mark(vUp)

        Self.logger.notice("[Insertion] synthetic marker=\(VoiceInputSyntheticEvent.marker, privacy: .public)")
        Self.logger.notice("[Insertion] posting V down via cghidEventTap")
        vDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(10))
        Self.logger.notice("[Insertion] posting V up via cghidEventTap")
        vUp.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor
final class SystemTextInserter: TextInserting {
    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Insertion")

    private let accessibilityInserter: AccessibilityTextInserting
    private let applicationActivator: TargetApplicationActivating
    private let pasteEventPoster: PasteEventPosting
    private let pasteboard: NSPasteboard
    private let activationTimeout: Duration
    private let clipboardRestoreDelay: Duration
    private let accessibilityIsTrusted: @MainActor () -> Bool
    private let useAXDirectInsertion: Bool
    private let secureEventInputIsEnabled: @MainActor () -> Bool
    private let sleep: @MainActor (Duration) async -> Void
    private var pendingRestoration: PendingClipboardRestoration?
    private var restorationTask: Task<Void, Never>?

    private struct PendingClipboardRestoration {
        let id: UUID
        let snapshot: PasteboardSnapshot
        let expectedChangeCount: Int
    }

    convenience init() {
        self.init(
            accessibilityInserter: SystemAccessibilityTextInserter(),
            applicationActivator: SystemTargetApplicationActivator(),
            pasteEventPoster: CGPasteEventPoster(),
            pasteboard: .general
        )
    }

    init(
        accessibilityInserter: AccessibilityTextInserting,
        applicationActivator: TargetApplicationActivating,
        pasteEventPoster: PasteEventPosting,
        pasteboard: NSPasteboard,
        activationTimeout: Duration = .milliseconds(800),
        clipboardRestoreDelay: Duration = .seconds(2),
        accessibilityIsTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        useAXDirectInsertion: Bool = false,
        secureEventInputIsEnabled: @escaping @MainActor () -> Bool = {
            IsSecureEventInputEnabled()
        },
        sleep: @escaping @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.accessibilityInserter = accessibilityInserter
        self.applicationActivator = applicationActivator
        self.pasteEventPoster = pasteEventPoster
        self.pasteboard = pasteboard
        self.activationTimeout = activationTimeout
        self.clipboardRestoreDelay = clipboardRestoreDelay
        self.accessibilityIsTrusted = accessibilityIsTrusted
        self.useAXDirectInsertion = useAXDirectInsertion
        self.secureEventInputIsEnabled = secureEventInputIsEnabled
        self.sleep = sleep
    }

    func insert(_ text: String, into target: InsertionTarget) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.notice("[Insertion] empty transcript; nothing to insert")
            return
        }
        guard target.subrole != (kAXSecureTextFieldSubrole as String) else {
            Self.logger.error("[Insertion][ERROR] captured target is a secure text field")
            throw TextInsertionError.secureField
        }
        guard applicationActivator.isApplicationAvailable(
            processIdentifier: target.processIdentifier
        ) else {
            Self.logger.error("[Insertion][ERROR] captured target PID=\(target.processIdentifier, privacy: .public) is no longer available")
            throw TextInsertionError.targetApplicationUnavailable
        }

        let currentFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        Self.logger.notice("[Insertion] transcript ready length=\(text.count, privacy: .public)")
        Self.logger.notice("[Insertion] target PID=\(target.processIdentifier, privacy: .public)")
        Self.logger.notice("[Insertion] target bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public)")
        Self.logger.notice("[Insertion] target role=\(target.role ?? "unknown", privacy: .public)")
        Self.logger.notice("[Insertion] current frontmost PID=\(currentFrontmostPID, privacy: .public)")
        if useAXDirectInsertion {
            Self.logger.notice("[Insertion] attempting AX insertion")
            let axResult: AXTextInsertionResult
            do {
                axResult = try accessibilityInserter.insert(text, into: target)
            } catch {
                Self.logger.error("[Insertion][ERROR] AX insertion rejected: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            switch axResult {
            case .succeeded:
                Self.logger.notice("[Insertion] AX write supported=true")
                Self.logger.notice("[Insertion] AX set result=success")
                return
            case .unsupported(let reason):
                Self.logger.notice("[Insertion] AX write supported=false: \(reason, privacy: .public)")
            case .failed(let error, let operation):
                Self.logger.error("[Insertion] AX set result=\(axErrorName(error), privacy: .public) (\(error.rawValue, privacy: .public)), operation=\(operation, privacy: .public)")
            }
        } else {
            Self.logger.notice("[Insertion] AX direct insertion disabled; testing clipboard path")
        }

        try await pasteUsingClipboard(text, target: target)
    }

    private func pasteUsingClipboard(_ text: String, target: InsertionTarget) async throws {
        Self.logger.notice("[Insertion] attempting clipboard fallback")
        guard !secureEventInputIsEnabled() else {
            Self.logger.error("[Insertion][ERROR] secure event input is enabled; paste cancelled")
            throw TextInsertionError.secureField
        }
        restorePendingClipboardNow(reason: "superseded by a new insertion")
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let originalChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            if pasteboard.changeCount != originalChangeCount { snapshot.restore(to: pasteboard) }
            Self.logger.error("[Insertion][ERROR] failed to write transcript to clipboard")
            throw TextInsertionError.clipboardWriteFailed
        }
        guard pasteboard.string(forType: .string) == text else {
            snapshot.restore(to: pasteboard)
            Self.logger.error("[Insertion][ERROR] clipboard verification failed")
            throw TextInsertionError.clipboardVerificationFailed
        }
        let voiceInputChangeCount = pasteboard.changeCount
        Self.logger.notice("[Insertion] clipboard prepared")

        guard accessibilityIsTrusted() else {
            restoreClipboardIfOwned(snapshot, expectedChangeCount: voiceInputChangeCount)
            Self.logger.error("[Insertion][ERROR] Accessibility permission is not trusted")
            throw TextInsertionError.accessibilityPermissionMissing
        }

        let alreadyFrontmost = applicationActivator.isFrontmost(
            processIdentifier: target.processIdentifier
        )
        Self.logger.notice("[Insertion] target frontmost=\(alreadyFrontmost, privacy: .public)")
        if !alreadyFrontmost {
            Self.logger.notice("[Insertion] target activation requested")
            let activated = await applicationActivator.activate(
                processIdentifier: target.processIdentifier,
                timeout: activationTimeout
            )
            Self.logger.notice("[Insertion] target frontmost=\(activated, privacy: .public)")
            guard activated else {
                restoreClipboardIfOwned(snapshot, expectedChangeCount: voiceInputChangeCount)
                Self.logger.error("[Insertion][ERROR] failed to activate target PID=\(target.processIdentifier, privacy: .public)")
                throw TextInsertionError.targetActivationFailed
            }
            logFocusRestoration(accessibilityInserter.restoreFocus(to: target))
            await sleep(.milliseconds(100))
        } else {
            Self.logger.notice("[Insertion] focus restore result=preserved (target remained frontmost)")
        }

        await sleep(.milliseconds(100))
        Self.logger.notice("[Insertion] sending Cmd+V")
        guard await pasteEventPoster.postPaste(to: target.processIdentifier) else {
            restoreClipboardIfOwned(snapshot, expectedChangeCount: voiceInputChangeCount)
            Self.logger.error("[Insertion][ERROR] failed to create or post Cmd+V")
            throw TextInsertionError.pasteEventCreationFailed
        }

        scheduleClipboardRestoration(
            snapshot,
            expectedChangeCount: voiceInputChangeCount
        )
        Self.logger.notice("[Insertion] paste fallback dispatched")
    }

    func waitForPendingClipboardRestoration() async {
        let task = restorationTask
        await task?.value
    }

    private func scheduleClipboardRestoration(
        _ snapshot: PasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        let pending = PendingClipboardRestoration(
            id: UUID(),
            snapshot: snapshot,
            expectedChangeCount: expectedChangeCount
        )
        pendingRestoration = pending
        restorationTask = Task { @MainActor in
            await sleep(clipboardRestoreDelay)
            guard !Task.isCancelled,
                  pendingRestoration?.id == pending.id else { return }
            restoreClipboardIfOwned(
                pending.snapshot,
                expectedChangeCount: pending.expectedChangeCount
            )
            pendingRestoration = nil
            restorationTask = nil
        }
    }

    private func restorePendingClipboardNow(reason: String) {
        restorationTask?.cancel()
        restorationTask = nil
        guard let pending = pendingRestoration else { return }
        restoreClipboardIfOwned(
            pending.snapshot,
            expectedChangeCount: pending.expectedChangeCount
        )
        pendingRestoration = nil
        Self.logger.debug("[Insertion] pending clipboard restoration completed: \(reason, privacy: .public)")
    }

    private func logFocusRestoration(_ result: AXFocusRestorationResult) {
        switch result {
        case .succeeded:
            Self.logger.notice("[Insertion] focus restore result=success")
        case .unavailable(let reason):
            Self.logger.notice("[Insertion] focus restore result=unavailable: \(reason, privacy: .public)")
        case .failed(let error, let operation):
            Self.logger.error("[Insertion] focus restore result=\(axErrorName(error), privacy: .public) (\(error.rawValue, privacy: .public)), operation=\(operation, privacy: .public)")
        }
    }

    private func restoreClipboardIfOwned(
        _ snapshot: PasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        guard pasteboard.changeCount == expectedChangeCount else {
            Self.logger.debug("[Insertion] clipboard changed by user; preserving new contents")
            return
        }
        snapshot.restore(to: pasteboard)
        Self.logger.debug("[Insertion] previous clipboard restored")
    }
}

struct PasteboardSnapshot {
    struct Item {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.values {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
