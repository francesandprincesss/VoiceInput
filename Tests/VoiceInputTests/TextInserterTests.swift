import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Testing
@testable import VoiceInput

@Suite("Text insertion", .serialized)
@MainActor
struct TextInserterTests {
    @Test("Successful AX insertion does not use clipboard fallback")
    func successfulAXInsertion() async throws {
        let context = Context(axResult: .succeeded)
        context.pasteboard.setString("original", forType: .string)

        try await context.inserter.insert("Привет", into: context.target)

        #expect(context.accessibility.insertedTexts == ["Привет"])
        #expect(context.activator.activationPIDs.isEmpty)
        #expect(context.poster.postedPIDs.isEmpty)
        #expect(context.pasteboard.string(forType: .string) == "original")
    }

    @Test("Production mode uses clipboard even when AX would report success")
    func productionModePrefersClipboard() async throws {
        let context = Context(axResult: .succeeded, useAXDirectInsertion: false)
        context.activator.frontmost = true

        try await context.inserter.insert("HELLO_FROM_VOICEINPUT", into: context.target)

        #expect(context.accessibility.insertedTexts.isEmpty)
        #expect(context.activator.activationPIDs.isEmpty)
        #expect(context.poster.postedPIDs == [context.target.processIdentifier])
    }

    @Test("Unsupported AX insertion falls back to clipboard paste")
    func unsupportedAXFallsBack() async throws {
        let context = Context(axResult: .unsupported("not settable"))

        try await context.inserter.insert("text", into: context.target)

        #expect(context.activator.activationPIDs == [context.target.processIdentifier])
        #expect(context.poster.postedPIDs == [context.target.processIdentifier])
    }

    @Test("Frontmost target is pasted into without reactivation or focus changes")
    func frontmostTargetIsNotReactivated() async throws {
        let context = Context(axResult: .unsupported("not settable"))
        context.activator.frontmost = true

        try await context.inserter.insert("text", into: context.target)

        #expect(context.activator.activationPIDs.isEmpty)
        #expect(context.accessibility.restoredFocusPIDs.isEmpty)
        #expect(context.poster.postedPIDs == [context.target.processIdentifier])
    }

    @Test("Non-frontmost target is activated and focused before paste")
    func nonFrontmostTargetIsActivated() async throws {
        let context = Context(axResult: .unsupported("not settable"))

        try await context.inserter.insert("text", into: context.target)

        #expect(context.activator.activationPIDs == [context.target.processIdentifier])
        #expect(context.accessibility.restoredFocusPIDs == [context.target.processIdentifier])
        #expect(context.poster.postedPIDs == [context.target.processIdentifier])
    }

    @Test("AX error falls back to clipboard paste")
    func axErrorFallsBack() async throws {
        let context = Context(axResult: .failed(.cannotComplete, operation: "set AXSelectedText"))

        try await context.inserter.insert("text", into: context.target)

        #expect(context.activator.activationPIDs.count == 1)
        #expect(context.poster.postedPIDs.count == 1)
    }

    @Test("Clipboard items and all their data types are restored after paste")
    func clipboardIsRestored() async throws {
        let context = Context(axResult: .unsupported("not supported"))
        let customType = NSPasteboard.PasteboardType("com.local.voiceinput.test-data")
        let item = NSPasteboardItem()
        item.setString("original text", forType: .string)
        item.setData(Data([0x01, 0x02, 0x03]), forType: customType)
        context.pasteboard.writeObjects([item])

        try await context.inserter.insert("recognized text", into: context.target)
        await context.inserter.waitForPendingClipboardRestoration()

        #expect(context.pasteboard.string(forType: .string) == "original text")
        #expect(context.pasteboard.data(forType: customType) == Data([0x01, 0x02, 0x03]))
    }

    @Test("Clipboard contains the complete Russian Unicode transcript when paste is posted")
    func clipboardContainsUnicodeTranscript() async throws {
        let context = Context(axResult: .unsupported("not supported"))
        let transcript = "Привет, это проверка голосового ввода."
        var valueAtPaste: String?
        context.poster.onPost = {
            valueAtPaste = context.pasteboard.string(forType: .string)
        }

        try await context.inserter.insert(transcript, into: context.target)

        #expect(valueAtPaste == transcript)
        #expect(context.poster.postedPIDs.count == 1)
    }

    @Test("Clipboard is not restored when the user changes it")
    func userClipboardChangeIsPreserved() async throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("original", forType: .string)
        let accessibility = AccessibilityMock(result: .unsupported("not supported"))
        let activator = ApplicationActivatorMock()
        let poster = PasteEventPosterMock()
        var sleepCount = 0
        let inserter = SystemTextInserter(
            accessibilityInserter: accessibility,
            applicationActivator: activator,
            pasteEventPoster: poster,
            pasteboard: pasteboard,
            activationTimeout: .zero,
            clipboardRestoreDelay: .zero,
            accessibilityIsTrusted: { true },
            secureEventInputIsEnabled: { false },
            sleep: { _ in
                sleepCount += 1
                if sleepCount == 3 {
                    pasteboard.clearContents()
                    pasteboard.setString("user value", forType: .string)
                }
            }
        )

        try await inserter.insert("recognized text", into: makeTarget())
        await inserter.waitForPendingClipboardRestoration()

        #expect(pasteboard.string(forType: .string) == "user value")
    }

    @Test("Clipboard restoration does not block insertion completion")
    func clipboardRestorationIsNonBlocking() async throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("original", forType: .string)
        let gate = RestorationGate()
        let inserter = SystemTextInserter(
            accessibilityInserter: AccessibilityMock(result: .unsupported("disabled")),
            applicationActivator: ApplicationActivatorMock(frontmost: true),
            pasteEventPoster: PasteEventPosterMock(),
            pasteboard: pasteboard,
            activationTimeout: .zero,
            clipboardRestoreDelay: .seconds(2),
            accessibilityIsTrusted: { true },
            secureEventInputIsEnabled: { false },
            sleep: { duration in
                guard duration == .seconds(2) else { return }
                await gate.wait()
            }
        )

        try await inserter.insert("recognized text", into: makeTarget())
        for _ in 0..<20 where !gate.hasWaiter { await Task.yield() }

        #expect(gate.hasWaiter)
        #expect(pasteboard.string(forType: .string) == "recognized text")

        gate.resume()
        await inserter.waitForPendingClipboardRestoration()
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test("Empty transcript performs no insertion")
    func emptyTranscriptDoesNothing() async throws {
        let context = Context(axResult: .succeeded)

        try await context.inserter.insert(" \n\t ", into: context.target)

        #expect(context.accessibility.insertedTexts.isEmpty)
        #expect(context.activator.activationPIDs.isEmpty)
        #expect(context.poster.postedPIDs.isEmpty)
    }

    @Test("Secure field is rejected without clipboard fallback")
    func secureFieldIsRejected() async {
        let context = Context(axResult: .succeeded)
        context.accessibility.error = TextInsertionError.secureField

        do {
            try await context.inserter.insert("secret", into: context.target)
            Issue.record("Expected secure-field insertion to fail")
        } catch {
            #expect(error as? TextInsertionError == .secureField)
        }

        #expect(context.activator.activationPIDs.isEmpty)
        #expect(context.poster.postedPIDs.isEmpty)
    }
}

@MainActor
private final class Context {
    let accessibility: AccessibilityMock
    let activator = ApplicationActivatorMock()
    let poster = PasteEventPosterMock()
    let pasteboard = makePasteboard()
    let target = makeTarget()
    let inserter: SystemTextInserter

    init(
        axResult: AXTextInsertionResult,
        useAXDirectInsertion: Bool = true
    ) {
        accessibility = AccessibilityMock(result: axResult)
        inserter = SystemTextInserter(
            accessibilityInserter: accessibility,
            applicationActivator: activator,
            pasteEventPoster: poster,
            pasteboard: pasteboard,
            activationTimeout: .zero,
            clipboardRestoreDelay: .zero,
            accessibilityIsTrusted: { true },
            useAXDirectInsertion: useAXDirectInsertion,
            secureEventInputIsEnabled: { false },
            sleep: { _ in }
        )
    }
}

@MainActor
private final class AccessibilityMock: AccessibilityTextInserting {
    let result: AXTextInsertionResult
    var error: Error?
    var insertedTexts: [String] = []
    var restoredFocusPIDs: [pid_t] = []

    init(result: AXTextInsertionResult) {
        self.result = result
    }

    func insert(_ text: String, into target: InsertionTarget) throws -> AXTextInsertionResult {
        insertedTexts.append(text)
        if let error { throw error }
        return result
    }

    func restoreFocus(to target: InsertionTarget) -> AXFocusRestorationResult {
        restoredFocusPIDs.append(target.processIdentifier)
        return .succeeded
    }
}

@MainActor
private final class ApplicationActivatorMock: TargetApplicationActivating {
    var available = true
    var frontmost = false
    var activationResult = true
    var activationPIDs: [pid_t] = []

    init(frontmost: Bool = false) {
        self.frontmost = frontmost
    }

    func isApplicationAvailable(processIdentifier: pid_t) -> Bool { available }
    func isFrontmost(processIdentifier: pid_t) -> Bool { frontmost }

    func activate(processIdentifier: pid_t, timeout: Duration) async -> Bool {
        activationPIDs.append(processIdentifier)
        return activationResult
    }
}

@MainActor
private final class RestorationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var hasWaiter: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class PasteEventPosterMock: PasteEventPosting {
    var result = true
    var postedPIDs: [pid_t] = []
    var onPost: (() -> Void)?

    func postPaste(to processIdentifier: pid_t) -> Bool {
        postedPIDs.append(processIdentifier)
        onPost?()
        return result
    }
}

@MainActor
private func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("VoiceInputTests-\(UUID().uuidString)"))
}

private func makeTarget(processIdentifier: pid_t = 41_234) -> InsertionTarget {
    InsertionTarget(
        processIdentifier: processIdentifier,
        bundleIdentifier: "com.example.target",
        focusedElement: nil,
        role: kAXTextAreaRole as String
    )
}
