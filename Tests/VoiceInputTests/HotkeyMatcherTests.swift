import CoreGraphics
import Testing
@testable import VoiceInput

private func modifierEvent(
    _ key: PhysicalModifierKey,
    down: Bool,
    flags: CGEventFlags? = nil
) -> HotkeyInputEvent {
    HotkeyInputEvent(
        type: .flagsChanged,
        keyCode: key.rawValue,
        flags: flags ?? (down ? key.eventFlag : []),
        physicalKeyIsDown: down
    )
}

private func keyEvent(
    _ type: HotkeyInputEventType,
    keyCode: UInt16,
    flags: CGEventFlags = [],
    repeat isAutoRepeat: Bool = false
) -> HotkeyInputEvent {
    HotkeyInputEvent(
        type: type,
        keyCode: keyCode,
        flags: flags,
        isAutoRepeat: isAutoRepeat
    )
}

private func verifyPhysicalSidesAreDistinct(
    left: PhysicalModifierKey,
    right: PhysicalModifierKey
) {
    var leftMatcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [left.rawValue])
    )
    #expect(leftMatcher.consume(modifierEvent(right, down: true)).action == nil)
    #expect(leftMatcher.isBoundKeyPhysicallyDown == false)
    #expect(leftMatcher.consume(modifierEvent(right, down: false)).action == nil)
    #expect(leftMatcher.consume(modifierEvent(left, down: true)).action == .pressed)

    var rightMatcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [right.rawValue])
    )
    #expect(rightMatcher.consume(modifierEvent(left, down: true)).action == nil)
    #expect(rightMatcher.isBoundKeyPhysicallyDown == false)
    #expect(rightMatcher.consume(modifierEvent(left, down: false)).action == nil)
    #expect(rightMatcher.consume(modifierEvent(right, down: true)).action == .pressed)
}

@Test("Left and right physical modifiers are distinct")
func leftAndRightModifiersAreDistinct() {
    verifyPhysicalSidesAreDistinct(left: .leftCommand, right: .rightCommand)
    verifyPhysicalSidesAreDistinct(left: .leftShift, right: .rightShift)
    verifyPhysicalSidesAreDistinct(left: .leftOption, right: .rightOption)
    verifyPhysicalSidesAreDistinct(left: .leftControl, right: .rightControl)
}

@Test("Fn never matches Command")
func fnDoesNotMatchCommand() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.function.rawValue])
    )

    let result = matcher.consume(modifierEvent(
        .leftCommand,
        down: true,
        flags: [.maskCommand, .maskSecondaryFn]
    ))
    #expect(result == .ignored)
    #expect(matcher.isBoundKeyPhysicallyDown == false)

    let wrongFnEdge = HotkeyInputEvent(
        type: .flagsChanged,
        keyCode: PhysicalModifierKey.function.rawValue,
        flags: .maskCommand,
        physicalKeyIsDown: true
    )
    #expect(matcher.consume(wrongFnEdge) == .ignored)
    #expect(matcher.isBoundKeyPhysicallyDown == false)
}

@Test("Fn shortcut ignores the complete Command-Tab sequence")
func fnIgnoresCommandTab() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.function.rawValue])
    )
    let tab: UInt16 = 48

    let noisyCommandFlags: CGEventFlags = [.maskCommand, .maskSecondaryFn]
    #expect(matcher.consume(modifierEvent(
        .leftCommand,
        down: true,
        flags: noisyCommandFlags
    )) == .ignored)
    #expect(matcher.consume(keyEvent(
        .keyDown,
        keyCode: tab,
        flags: noisyCommandFlags
    )) == .ignored)
    #expect(matcher.consume(keyEvent(
        .keyUp,
        keyCode: tab,
        flags: noisyCommandFlags
    )) == .ignored)
    #expect(matcher.consume(modifierEvent(
        .leftCommand,
        down: false,
        flags: .maskSecondaryFn
    )) == .ignored)
    #expect(matcher.isBoundKeyPhysicallyDown == false)
}

@Test("Rebind Left Command to Fn invalidates Left Command")
func rebindModifierInvalidatesOldBinding() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.leftCommand.rawValue])
    )
    #expect(matcher.consume(modifierEvent(.leftCommand, down: true)).action == .pressed)

    matcher.rebind(to: HotkeyShortcut(
        modifierKeyCodes: [PhysicalModifierKey.function.rawValue]
    ))

    #expect(matcher.isBoundKeyPhysicallyDown == false)
    #expect(matcher.consume(modifierEvent(.leftCommand, down: false)) == .ignored)
    #expect(matcher.consume(modifierEvent(.leftCommand, down: true)) == .ignored)
    #expect(matcher.consume(modifierEvent(.function, down: true)).action == .pressed)
}

@Test("Rebind A to B invalidates and stops suppressing A")
func rebindRegularKeyInvalidatesOldBinding() {
    let keyA: UInt16 = 0
    let keyB: UInt16 = 11
    var matcher = HotkeyMatcher(shortcut: HotkeyShortcut(keyCode: keyA))
    #expect(matcher.consume(keyEvent(.keyDown, keyCode: keyA)).action == .pressed)

    matcher.rebind(to: HotkeyShortcut(keyCode: keyB))

    #expect(matcher.isBoundKeyPhysicallyDown == false)
    #expect(matcher.consume(keyEvent(.keyUp, keyCode: keyA)) == .ignored)
    #expect(matcher.consume(keyEvent(.keyDown, keyCode: keyA)) == .ignored)
    let newResult = matcher.consume(keyEvent(.keyDown, keyCode: keyB))
    #expect(newResult.action == .pressed)
    #expect(newResult.suppress)
}

@Test("Unrelated flagsChanged events do not affect the bound modifier")
func unrelatedModifiersAreIgnored() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.function.rawValue])
    )
    #expect(matcher.consume(modifierEvent(.leftShift, down: true)) == .ignored)
    #expect(matcher.consume(modifierEvent(.rightOption, down: true)) == .ignored)
    #expect(matcher.consume(modifierEvent(.leftShift, down: false)) == .ignored)
    #expect(matcher.consume(modifierEvent(.rightOption, down: false)) == .ignored)
    #expect(matcher.isBoundKeyPhysicallyDown == false)
}

@Test("Push to Talk modifier produces exactly one press and one release")
func pushToTalkModifierEdgesAreUnique() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.function.rawValue])
    )
    var machine = DictationStateMachine()
    var actions: [HotkeyMatchAction] = []

    func apply(_ result: HotkeyMatchResult) {
        guard let action = result.action else { return }
        actions.append(action)
        switch action {
        case .pressed:
            machine.handle(.keyDown(isAutoRepeat: false), mode: .pushToTalk)
        case .released:
            machine.handle(.keyUp, mode: .pushToTalk)
        }
    }

    apply(matcher.consume(modifierEvent(.function, down: true)))
    apply(matcher.consume(modifierEvent(.function, down: true)))
    apply(matcher.consume(modifierEvent(.leftCommand, down: true)))
    apply(matcher.consume(modifierEvent(.leftCommand, down: false)))
    #expect(machine.state == .recording)
    apply(matcher.consume(modifierEvent(.function, down: false)))
    apply(matcher.consume(modifierEvent(.function, down: false)))

    #expect(actions == [.pressed, .released])
    #expect(machine.state == .processing)
}

@Test("Rebind clears stale pressed state")
func rebindClearsStalePressedState() {
    var matcher = HotkeyMatcher(shortcut: HotkeyShortcut(keyCode: 0))
    _ = matcher.consume(keyEvent(.keyDown, keyCode: 0))
    #expect(matcher.isBoundKeyPhysicallyDown)

    matcher.rebind(to: HotkeyShortcut(keyCode: 11))
    #expect(matcher.isBoundKeyPhysicallyDown == false)
    #expect(matcher.consume(keyEvent(.keyUp, keyCode: 0)) == .ignored)
}

@Test("Regular-key duplicate and autorepeat events do not add edges")
func duplicateAndAutorepeatEventsAreIgnored() {
    var matcher = HotkeyMatcher(shortcut: HotkeyShortcut(keyCode: 0))
    #expect(matcher.consume(keyEvent(.keyDown, keyCode: 0)).action == .pressed)
    #expect(matcher.consume(keyEvent(.keyDown, keyCode: 0)).action == nil)
    let repeated = matcher.consume(keyEvent(.keyDown, keyCode: 0, repeat: true))
    #expect(repeated.action == nil)
    #expect(repeated.suppress)
    #expect(matcher.consume(keyEvent(.keyUp, keyCode: 0)).action == .released)
    #expect(matcher.consume(keyEvent(.keyUp, keyCode: 0)) == .ignored)
}

@Test("Internal generated Cmd+V events are neither matched nor suppressed")
func internalSyntheticPasteIsIgnored() {
    var matcher = HotkeyMatcher(
        shortcut: HotkeyShortcut(modifierKeyCodes: [PhysicalModifierKey.leftCommand.rawValue])
    )
    let commandDown = HotkeyInputEvent(
        type: .flagsChanged,
        keyCode: PhysicalModifierKey.leftCommand.rawValue,
        flags: .maskCommand,
        physicalKeyIsDown: true,
        isInternalSynthetic: true
    )
    let vDown = HotkeyInputEvent(
        type: .keyDown,
        keyCode: 9,
        flags: .maskCommand,
        isInternalSynthetic: true
    )

    #expect(matcher.consume(commandDown) == .ignored)
    #expect(matcher.consume(vDown) == .ignored)
    #expect(matcher.isBoundKeyPhysicallyDown == false)
}

@Test("Generated CGEvents retain the VoiceInput internal marker")
func generatedCGEventMarkerRoundTrips() throws {
    let event = try #require(CGEvent(
        keyboardEventSource: CGEventSource(stateID: .privateState),
        virtualKey: 9,
        keyDown: true
    ))
    VoiceInputSyntheticEvent.mark(event)
    #expect(VoiceInputSyntheticEvent.isMarked(event))
}

@Test("Event tap returns the original marked synthetic event instead of suppressing it")
@MainActor
func markedSyntheticEventPassesThroughEventTap() throws {
    let manager = HotkeyManager(shortcut: HotkeyShortcut(keyCode: 9))
    var hotkeyEvents: [DictationHotkeyEvent] = []
    manager.onEvent = { hotkeyEvents.append($0) }
    let event = try #require(CGEvent(
        keyboardEventSource: CGEventSource(stateID: .hidSystemState),
        virtualKey: 9,
        keyDown: true
    ))
    event.flags = .maskCommand
    VoiceInputSyntheticEvent.mark(event)

    let suppress = manager.handle(type: .keyDown, event: event)
    let returned = hotkeyTapCallbackResult(event: event, suppress: suppress)

    #expect(suppress == false)
    #expect(returned != nil)
    #expect(returned?.takeUnretainedValue() === event)
    #expect(hotkeyEvents.isEmpty)
    #expect(manager.boundKeyIsDown == false)
}

@Test("HotkeyManager rebind A to B removes A from callbacks and suppression")
@MainActor
func managerRebindRegularKeyIntegration() {
    let keyA: UInt16 = 0
    let keyB: UInt16 = 11
    let manager = HotkeyManager(shortcut: HotkeyShortcut(keyCode: keyA))
    var events: [DictationHotkeyEvent] = []
    manager.onEvent = { events.append($0) }

    #expect(manager.process(keyEvent(.keyDown, keyCode: keyA)))
    #expect(events == [.keyDown(isAutoRepeat: false)])
    manager.rebind(to: HotkeyShortcut(keyCode: keyB))
    events.removeAll()

    #expect(manager.process(keyEvent(.keyUp, keyCode: keyA)) == false)
    #expect(manager.process(keyEvent(.keyDown, keyCode: keyA)) == false)
    #expect(events.isEmpty)
    #expect(manager.process(keyEvent(.keyDown, keyCode: keyB)))
    #expect(events == [.keyDown(isAutoRepeat: false)])
}

@Test("HotkeyManager rebind Left Command to Fn removes Left Command")
@MainActor
func managerRebindModifierIntegration() {
    let manager = HotkeyManager(shortcut: HotkeyShortcut(
        modifierKeyCodes: [PhysicalModifierKey.leftCommand.rawValue]
    ))
    var events: [DictationHotkeyEvent] = []
    manager.onEvent = { events.append($0) }

    #expect(manager.process(modifierEvent(.leftCommand, down: true)))
    manager.rebind(to: HotkeyShortcut(
        modifierKeyCodes: [PhysicalModifierKey.function.rawValue]
    ))
    events.removeAll()

    #expect(manager.process(modifierEvent(.leftCommand, down: false)) == false)
    #expect(manager.process(modifierEvent(.leftCommand, down: true)) == false)
    #expect(events.isEmpty)
    #expect(manager.process(modifierEvent(.function, down: true)))
    #expect(events == [.keyDown(isAutoRepeat: false)])
}

@Test("Event tap reports the permission that prevents startup")
@MainActor
func eventTapPermissionDiagnostics() {
    let manager = HotkeyManager(shortcut: .defaultShortcut)

    manager.updatePermissions(inputMonitoring: false, accessibility: false)
    #expect(manager.eventTapStatus == .inactiveMissingInputMonitoring)
    #expect(manager.eventTapIsActive == false)

    manager.updatePermissions(inputMonitoring: true, accessibility: false)
    #expect(manager.eventTapStatus == .inactiveMissingAccessibility)
    #expect(manager.eventTapIsActive == false)

    manager.updatePermissions(inputMonitoring: false, accessibility: true)
    #expect(manager.eventTapStatus == .inactiveMissingInputMonitoring)
    #expect(manager.eventTapIsActive == false)
}
