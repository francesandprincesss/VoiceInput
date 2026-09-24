import CoreGraphics

enum HotkeyInputEventType: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
}

struct HotkeyInputEvent: Equatable, Sendable {
    let type: HotkeyInputEventType
    let keyCode: UInt16
    let flagsRawValue: UInt64
    let isAutoRepeat: Bool
    /// Physical state for this exact modifier key. It disambiguates releasing
    /// one side while the other side of the same modifier family remains down.
    let physicalKeyIsDown: Bool?

    init(
        type: HotkeyInputEventType,
        keyCode: UInt16,
        flags: CGEventFlags = [],
        isAutoRepeat: Bool = false,
        physicalKeyIsDown: Bool? = nil
    ) {
        self.type = type
        self.keyCode = keyCode
        flagsRawValue = flags.rawValue
        self.isAutoRepeat = isAutoRepeat
        self.physicalKeyIsDown = physicalKeyIsDown
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: flagsRawValue) }
}

enum HotkeyMatchAction: Equatable, Sendable {
    case pressed
    case released
}

struct HotkeyMatchResult: Equatable, Sendable {
    let action: HotkeyMatchAction?
    let suppress: Bool

    static let ignored = HotkeyMatchResult(action: nil, suppress: false)
}

struct HotkeyMatcher: Sendable {
    private(set) var shortcut: HotkeyShortcut?
    private(set) var isBoundKeyPhysicallyDown = false

    private var activeModifiers: Set<PhysicalModifierKey> = []
    private var regularKeyIsDown = false

    init(shortcut: HotkeyShortcut?) {
        self.shortcut = shortcut
    }

    mutating func rebind(to shortcut: HotkeyShortcut?) {
        self.shortcut = shortcut
        resetPhysicalState()
    }

    mutating func resetPhysicalState() {
        activeModifiers.removeAll()
        regularKeyIsDown = false
        isBoundKeyPhysicallyDown = false
    }

    mutating func consume(_ event: HotkeyInputEvent) -> HotkeyMatchResult {
        guard let shortcut else { return .ignored }

        if event.type == .flagsChanged,
           let modifier = PhysicalModifierKey(rawValue: event.keyCode) {
            updatePhysicalModifier(modifier, from: event)
            guard shortcut.kind == .modifiersOnly,
                  shortcut.modifierSet.contains(modifier.rawValue) else {
                return .ignored
            }

            let allBoundModifiersAreDown = shortcut.modifierSet.allSatisfy {
                guard let key = PhysicalModifierKey(rawValue: $0) else { return false }
                return activeModifiers.contains(key)
            }
            let suppress = shortcut.modifierKeyCodes.count == 1

            if allBoundModifiersAreDown, !isBoundKeyPhysicallyDown {
                isBoundKeyPhysicallyDown = true
                return HotkeyMatchResult(action: .pressed, suppress: suppress)
            }

            if isBoundKeyPhysicallyDown, !allBoundModifiersAreDown {
                isBoundKeyPhysicallyDown = false
                return HotkeyMatchResult(action: .released, suppress: suppress)
            }

            return HotkeyMatchResult(action: nil, suppress: suppress && isBoundKeyPhysicallyDown)
        }

        guard shortcut.kind == .key, shortcut.keyCode == event.keyCode else {
            return .ignored
        }

        if event.type == .keyDown {
            if event.isAutoRepeat {
                return HotkeyMatchResult(action: nil, suppress: regularKeyIsDown)
            }
            guard !regularKeyIsDown,
                  activeModifiers.map(\.rawValue).asSet == shortcut.modifierSet else {
                return .ignored
            }
            regularKeyIsDown = true
            isBoundKeyPhysicallyDown = true
            return HotkeyMatchResult(action: .pressed, suppress: true)
        }

        if event.type == .keyUp, regularKeyIsDown {
            regularKeyIsDown = false
            isBoundKeyPhysicallyDown = false
            return HotkeyMatchResult(action: .released, suppress: true)
        }

        return .ignored
    }

    private mutating func updatePhysicalModifier(
        _ modifier: PhysicalModifierKey,
        from event: HotkeyInputEvent
    ) {
        let familyFlagIsSet = event.flags.contains(modifier.eventFlag)
        let wasDown = activeModifiers.contains(modifier)

        if !wasDown, familyFlagIsSet {
            // The exact event keyCode is the physical identity. The family flag
            // confirms this is the down edge (especially important for Fn).
            activeModifiers.insert(modifier)
            return
        }

        if wasDown,
           (!familyFlagIsSet || event.physicalKeyIsDown == false) {
            activeModifiers.remove(modifier)
        }
    }
}

private extension Sequence where Element: Hashable {
    var asSet: Set<Element> { Set(self) }
}
