import CoreGraphics
import Foundation

struct HotkeyShortcut: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case key
        case modifiersOnly
    }

    let kind: Kind
    let keyCode: UInt16?
    let modifierKeyCodes: [UInt16]

    init(keyCode: UInt16, modifierKeyCodes: Set<UInt16> = []) {
        kind = .key
        self.keyCode = keyCode
        self.modifierKeyCodes = modifierKeyCodes.sorted()
    }

    init(modifierKeyCodes: Set<UInt16>) {
        precondition(!modifierKeyCodes.isEmpty)
        kind = .modifiersOnly
        keyCode = nil
        self.modifierKeyCodes = modifierKeyCodes.sorted()
    }

    static let defaultShortcut = HotkeyShortcut(
        modifierKeyCodes: [PhysicalModifierKey.rightCommand.rawValue]
    )

    var modifierSet: Set<UInt16> { Set(modifierKeyCodes) }

    var displayName: String {
        let modifiers = modifierKeyCodes.map(Self.keyName).joined(separator: " + ")
        guard kind == .key, let keyCode else { return modifiers }
        let key = Self.keyName(keyCode)
        return modifiers.isEmpty ? key : "\(modifiers) + \(key)"
    }

    static let modifierKeyCodes = Set(PhysicalModifierKey.allCases.map(\.rawValue))

    static func isModifier(_ keyCode: UInt16) -> Bool {
        PhysicalModifierKey(rawValue: keyCode) != nil
    }

    static func keyName(_ keyCode: UInt16) -> String {
        PhysicalModifierKey(rawValue: keyCode)?.displayName
            ?? functionKeyNames[keyCode]
            ?? regularKeyNames[keyCode]
            ?? "Key \(keyCode)"
    }

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let regularKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Escape", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +",
        71: "Clear", 75: "Keypad /", 76: "Enter", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
        91: "Keypad 8", 92: "Keypad 9", 114: "Help", 115: "Home",
        116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
    ]
}
