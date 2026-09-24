enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case processing
    case success
}

enum DictationHotkeyEvent: Equatable, Sendable {
    case keyDown(isAutoRepeat: Bool)
    case keyUp
}

struct DictationStateMachine: Sendable {
    private(set) var state: DictationState = .idle

    @discardableResult
    mutating func handle(_ event: DictationHotkeyEvent, mode: HotkeyMode) -> Bool {
        let previous = state

        switch (mode, event, state) {
        case (_, .keyDown(isAutoRepeat: true), _):
            break
        case (.toggle, .keyDown, .idle):
            state = .recording
        case (.toggle, .keyDown, .recording):
            state = .processing
        case (.pushToTalk, .keyDown, .idle):
            state = .recording
        case (.pushToTalk, .keyUp, .recording):
            state = .processing
        default:
            break
        }

        return state != previous
    }

    @discardableResult
    mutating func processingDidFinish() -> Bool {
        guard state == .processing else { return false }
        state = .success
        return true
    }

    @discardableResult
    mutating func successDidFinish() -> Bool {
        guard state == .success else { return false }
        state = .idle
        return true
    }
}
