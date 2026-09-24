import AppKit
@preconcurrency import ApplicationServices
import OSLog

struct InsertionTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let focusedElement: AXUIElement?
    let focusedWindow: AXUIElement?
    let role: String?
    let subrole: String?

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String? = nil,
        focusedElement: AXUIElement?,
        focusedWindow: AXUIElement? = nil,
        role: String? = nil,
        subrole: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.focusedElement = focusedElement
        self.focusedWindow = focusedWindow
        self.role = role
        self.subrole = subrole
    }
}

enum InsertionTargetError: LocalizedError {
    case noExternalApplication
    case noFocusedElement

    var errorDescription: String? {
        switch self {
        case .noExternalApplication: "No target application is active."
        case .noFocusedElement: "The active application has no accessible focused field."
        }
    }
}

@MainActor
protocol InsertionTargetCapturing: AnyObject {
    func capture() throws -> InsertionTarget
}

@MainActor
final class AccessibilityInsertionTargetCapture: InsertionTargetCapturing {
    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Insertion")

    func capture() throws -> InsertionTarget {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.bundleIdentifier != "com.local.voiceinput" else {
            throw InsertionTargetError.noExternalApplication
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Self.logger.error("[Insertion][ERROR] focused element capture failed: AXError=\(axErrorName(result), privacy: .public) (\(result.rawValue, privacy: .public))")
            throw InsertionTargetError.noFocusedElement
        }
        let focused = axElement(from: value)
        let window = copyElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement)
        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: focused)
        let subrole = copyStringAttribute(kAXSubroleAttribute as CFString, from: focused)
        let target = InsertionTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            focusedElement: focused,
            focusedWindow: window,
            role: role,
            subrole: subrole
        )
        Self.logger.notice("[Insertion] captured app PID=\(target.processIdentifier, privacy: .public)")
        Self.logger.notice("[Insertion] captured app bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public)")
        Self.logger.notice("[Insertion] captured focused element role=\(target.role ?? "unknown", privacy: .public), subrole=\(target.subrole ?? "none", privacy: .public)")
        return target
    }

    private func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return axElement(from: value)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func axElement(from value: CFTypeRef) -> AXUIElement {
        Unmanaged<AXUIElement>
            .fromOpaque(Unmanaged.passUnretained(value).toOpaque())
            .takeUnretainedValue()
    }
}

func axErrorName(_ error: AXError) -> String {
    switch error {
    case .success: "success"
    case .failure: "failure"
    case .illegalArgument: "illegalArgument"
    case .invalidUIElement: "invalidUIElement"
    case .invalidUIElementObserver: "invalidUIElementObserver"
    case .cannotComplete: "cannotComplete"
    case .attributeUnsupported: "attributeUnsupported"
    case .actionUnsupported: "actionUnsupported"
    case .notificationUnsupported: "notificationUnsupported"
    case .notImplemented: "notImplemented"
    case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
    case .notificationNotRegistered: "notificationNotRegistered"
    case .apiDisabled: "apiDisabled"
    case .noValue: "noValue"
    case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: "notEnoughPrecision"
    @unknown default: "unknown"
    }
}
