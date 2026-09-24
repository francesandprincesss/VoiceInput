import Testing
@testable import VoiceInput

@Test("Toggle moves idle to recording to processing")
func toggleTransitions() {
    var machine = DictationStateMachine()

    machine.handle(.keyDown(isAutoRepeat: false), mode: .toggle)
    #expect(machine.state == .recording)

    machine.handle(.keyDown(isAutoRepeat: false), mode: .toggle)
    #expect(machine.state == .processing)
}

@Test("Push to Talk records while held and processes on release")
func pushToTalkTransitions() {
    var machine = DictationStateMachine()

    machine.handle(.keyDown(isAutoRepeat: false), mode: .pushToTalk)
    #expect(machine.state == .recording)

    machine.handle(.keyUp, mode: .pushToTalk)
    #expect(machine.state == .processing)
}

@Test("Autorepeat does not create another transition")
func autorepeatIsIgnored() {
    var toggleMachine = DictationStateMachine()
    toggleMachine.handle(.keyDown(isAutoRepeat: false), mode: .toggle)
    toggleMachine.handle(.keyDown(isAutoRepeat: true), mode: .toggle)
    #expect(toggleMachine.state == .recording)

    var pushToTalkMachine = DictationStateMachine()
    pushToTalkMachine.handle(.keyDown(isAutoRepeat: false), mode: .pushToTalk)
    pushToTalkMachine.handle(.keyDown(isAutoRepeat: true), mode: .pushToTalk)
    #expect(pushToTalkMachine.state == .recording)
}
