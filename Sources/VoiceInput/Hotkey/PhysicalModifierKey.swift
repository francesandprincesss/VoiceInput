import AppKit
import CoreGraphics

/// Physical macOS modifier keys using the virtual key codes declared by
/// HIToolbox/Events.h (`kVK_*`). Left and right keys are distinct identities.
enum PhysicalModifierKey: UInt16, CaseIterable, Codable, Sendable {
    case rightCommand = 0x36
    case leftCommand = 0x37
    case leftShift = 0x38
    case leftOption = 0x3A
    case leftControl = 0x3B
    case rightShift = 0x3C
    case rightOption = 0x3D
    case rightControl = 0x3E
    case function = 0x3F

    var displayName: String {
        switch self {
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .leftControl: "Left Control"
        case .rightControl: "Right Control"
        case .function: "Fn"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand: .maskCommand
        case .leftShift, .rightShift: .maskShift
        case .leftOption, .rightOption: .maskAlternate
        case .leftControl, .rightControl: .maskControl
        case .function: .maskSecondaryFn
        }
    }

    var appKitFlag: NSEvent.ModifierFlags {
        switch self {
        case .leftCommand, .rightCommand: .command
        case .leftShift, .rightShift: .shift
        case .leftOption, .rightOption: .option
        case .leftControl, .rightControl: .control
        case .function: .function
        }
    }
}
