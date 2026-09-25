import Foundation
import Testing
@testable import VoiceInput

@Suite("Dictation pipeline", .serialized)
@MainActor
struct DictationCoordinatorTests {
    @Test("Starting dictation starts the recorder")
    func startCallsRecorder() {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        #expect(context.recorder.startCount == 1)
        #expect(context.coordinator.state == .recording)
    }

    @Test("Recorder start failure returns to idle and does not transcribe")
    func recorderStartFailure() {
        let context = Context()
        context.recorder.startError = TestFailure.audioStart
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .pushToTalk)

        #expect(context.coordinator.state == .idle)
        #expect(context.speech.transcriptionCount == 0)
        #expect(context.recorder.cancelCount == 1)
    }

    @Test("Overlay is explicitly returned to idle after recorder failure")
    func overlayIsNotLeftRecording() {
        let context = Context()
        context.recorder.startError = TestFailure.audioStart
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)

        #expect(context.presenter.states.last == .idle)
        #expect(!context.presenter.states.contains(.recording))
    }

    @Test("Toggle stop transcribes once, inserts, and saves History")
    func successfulTogglePipeline() async {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await context.coordinator.waitForCurrentOperation()

        #expect(context.recorder.stopCount == 1)
        #expect(context.speech.transcriptionCount == 1)
        #expect(context.inserter.values == ["recognized text"])
        #expect(context.history.values == ["recognized text"])
        #expect(context.presenter.states.contains(.processing))
        #expect(context.presenter.states.contains(.success))
        #expect(context.coordinator.state == .idle)
    }

    @Test("Successful insertion presents success before returning to idle")
    func successThenIdle() async {
        let context = Context()
        await context.runToggle()

        let successIndex = context.presenter.states.firstIndex(of: .success)
        let idleIndex = context.presenter.states.lastIndex(of: .idle)
        #expect(successIndex != nil)
        #expect(idleIndex != nil)
        #expect(successIndex! < idleIndex!)
    }

    @Test("Recording changes to processing only after recorder stop completes")
    func processingStartsAfterRecorderStops() async {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await context.coordinator.waitForCurrentOperation()

        let stopIndex = context.events.values.firstIndex(of: "recorder stopped")
        let processingIndex = context.events.values.firstIndex(of: "state processing")
        #expect(stopIndex != nil)
        #expect(processingIndex != nil)
        #expect(stopIndex! < processingIndex!)
    }

    @Test("Transcription completion alone does not show success while insertion is pending")
    func successWaitsForInsertion() async {
        let context = Context()
        context.inserter.shouldSuspend = true
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await waitUntil { !context.inserter.values.isEmpty }

        #expect(context.speech.transcriptionCount == 1)
        #expect(context.coordinator.state == .processing)
        #expect(!context.presenter.states.contains(.success))

        context.inserter.resume()
        await context.coordinator.waitForCurrentOperation()
        #expect(context.presenter.states.contains(.success))
        #expect(context.coordinator.state == .idle)
    }

    @Test("Processing remains active for real transcription work without a fixed completion")
    func processingTracksTranscription() async {
        let context = Context()
        context.speech.shouldSuspend = true
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await waitUntil { context.speech.transcriptionCount == 1 }

        #expect(context.coordinator.state == .processing)
        #expect(!context.presenter.states.contains(.success))

        context.speech.resume()
        await context.coordinator.waitForCurrentOperation()
        #expect(context.coordinator.state == .idle)
    }

    @Test("Push to Talk stops on release")
    func pushToTalkPipeline() async {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .pushToTalk)
        #expect(context.coordinator.state == .recording)
        context.coordinator.handleHotkey(.keyUp, mode: .pushToTalk)
        await context.coordinator.waitForCurrentOperation()
        #expect(context.recorder.stopCount == 1)
        #expect(context.speech.transcriptionCount == 1)
        #expect(context.coordinator.state == .idle)
    }

    @Test("Failed transcription does not insert")
    func failedTranscription() async {
        let context = Context()
        context.speech.error = TestFailure.transcription
        await context.runToggle()
        #expect(context.inserter.values.isEmpty)
        #expect(context.history.values.isEmpty)
        #expect(context.coordinator.state == .idle)
    }

    @Test("Failed insertion still preserves the transcript in History")
    func failedInsertion() async {
        let context = Context()
        context.inserter.error = TestFailure.insertion
        await context.runToggle()
        #expect(context.inserter.values == ["recognized text"])
        #expect(context.history.values == ["recognized text"])
        #expect(!context.presenter.states.contains(.success))
        #expect(context.coordinator.state == .idle)
    }

    @Test("Insertion target captured at start is preserved during processing")
    func insertionTargetIsPreserved() async {
        let context = Context()
        context.capture.processIdentifier = 101
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.capture.processIdentifier = 202
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await context.coordinator.waitForCurrentOperation()

        #expect(context.capture.captureCount == 1)
        #expect(context.inserter.targetPIDs == [101])
    }

    @Test("Hotkey while processing cannot start a second task")
    func processingIgnoresHotkey() async {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        #expect(context.recorder.startCount == 1)
        await context.coordinator.waitForCurrentOperation()
        #expect(context.speech.transcriptionCount == 1)
    }

    @Test("Autorepeat does not stop a recording")
    func autorepeatIgnored() {
        let context = Context()
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        context.coordinator.handleHotkey(.keyDown(isAutoRepeat: true), mode: .toggle)
        #expect(context.recorder.startCount == 1)
        #expect(context.recorder.stopCount == 0)
        #expect(context.coordinator.state == .recording)
    }

    @Test("Switching speech mode does not break DictationCoordinator")
    func coordinatorUsesCurrentRoute() async {
        let local = SpeechMock()
        let api = SpeechMock()
        let router = SpeechRecognizerRouter(
            mode: .local,
            localRecognizer: local,
            apiRecognizer: api
        )
        let recorder = RecorderMock()
        let coordinator = DictationCoordinator(
            recorder: recorder,
            speech: router,
            targetCapture: TargetCaptureMock(),
            textInserter: InserterMock(),
            history: HistoryMock(),
            presenter: PresenterMock(),
            language: { .automatic },
            successDisplayDuration: .zero
        )

        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await coordinator.waitForCurrentOperation()
        router.setMode(.api)
        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await coordinator.waitForCurrentOperation()

        #expect(local.transcriptionCount == 1)
        #expect(api.transcriptionCount == 1)
        #expect(coordinator.state == .idle)
    }
}

@MainActor
private final class Context {
    let recorder = RecorderMock()
    let speech = SpeechMock()
    let capture = TargetCaptureMock()
    let inserter = InserterMock()
    let history = HistoryMock()
    let presenter = PresenterMock()
    let coordinator: DictationCoordinator
    let events = EventTrace()

    init() {
        recorder.onStopCompleted = { [events] in events.values.append("recorder stopped") }
        presenter.onApply = { [events] state in events.values.append("state \(state)") }
        coordinator = DictationCoordinator(
            recorder: recorder,
            speech: speech,
            targetCapture: capture,
            textInserter: inserter,
            history: history,
            presenter: presenter,
            language: { .automatic },
            successDisplayDuration: .zero
        )
    }

    func runToggle() async {
        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        coordinator.handleHotkey(.keyDown(isAutoRepeat: false), mode: .toggle)
        await coordinator.waitForCurrentOperation()
    }
}

@MainActor
private final class RecorderMock: AudioRecordingService {
    var startCount = 0
    var stopCount = 0
    var cancelCount = 0
    var startError: Error?
    var onStopCompleted: (() -> Void)?
    func startRecording() throws {
        startCount += 1
        if let startError { throw startError }
    }
    func stopRecording() async throws -> CapturedAudio {
        stopCount += 1
        onStopCompleted?()
        return CapturedAudio(samples: [0.1, 0.2], sampleRate: 16_000)
    }
    func cancelRecording() { cancelCount += 1 }
}

@MainActor
private final class SpeechMock: SpeechRecognizer {
    var status: SpeechModelStatus = .ready
    var transcriptionCount = 0
    var error: Error?
    var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    func prepare() {}
    func transcribe(_ audio: CapturedAudio, language: SpeechRecognitionLanguage) async throws -> String {
        transcriptionCount += 1
        if shouldSuspend {
            await withCheckedContinuation { continuation = $0 }
        }
        if let error { throw error }
        return "recognized text"
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class TargetCaptureMock: InsertionTargetCapturing {
    var processIdentifier: pid_t = 42
    var captureCount = 0

    func capture() throws -> InsertionTarget {
        captureCount += 1
        return InsertionTarget(processIdentifier: processIdentifier, focusedElement: nil)
    }
}

@MainActor
private final class InserterMock: TextInserting {
    var values: [String] = []
    var targetPIDs: [pid_t] = []
    var error: Error?
    var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    func insert(_ text: String, into target: InsertionTarget) async throws {
        values.append(text)
        targetPIDs.append(target.processIdentifier)
        if shouldSuspend {
            await withCheckedContinuation { continuation = $0 }
        }
        if let error { throw error }
    }


    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class HistoryMock: HistoryStoring {
    var values: [String] = []
    func add(text: String) { values.append(text) }
}

@MainActor
private final class PresenterMock: DictationStatePresenting {
    var states: [DictationState] = []
    var onApply: ((DictationState) -> Void)?
    func apply(state: DictationState) {
        states.append(state)
        onApply?(state)
    }
}

@MainActor
private final class EventTrace {
    var values: [String] = []
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for an asynchronous test condition")
}

private enum TestFailure: Error {
    case audioStart
    case transcription
    case insertion
}
