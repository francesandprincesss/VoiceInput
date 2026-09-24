import Foundation

enum HotkeyMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case pushToTalk

    var id: Self { self }

    var title: String {
        switch self {
        case .toggle:
            "Toggle"
        case .pushToTalk:
            "Push to Talk"
        }
    }

    var explanation: String {
        switch self {
        case .toggle:
            "Press the hotkey to start recording. Press it again to stop."
        case .pushToTalk:
            "Hold the hotkey while recording. Release it to stop."
        }
    }
}
