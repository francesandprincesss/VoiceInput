import Foundation
import OSLog

@MainActor
protocol DictationStatePresenting: AnyObject {
    func apply(state: DictationState)
}

@MainActor
final class DictationCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Dictation")
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastError: String?

    private let recorder: AudioRecordingService
    private let speech: SpeechRecognizer
    private let targetCapture: InsertionTargetCapturing
    private let textInserter: TextInserting
    private let history: HistoryStoring
    private let presenter: DictationStatePresenting
    private let language: () -> SpeechRecognitionLanguage
    private let successDisplayDuration: Duration
    private var insertionTarget: InsertionTarget?
    private var processingTask: Task<Void, Never>?

    init(
        recorder: AudioRecordingService,
        speech: SpeechRecognizer,
        targetCapture: InsertionTargetCapturing,
        textInserter: TextInserting,
        history: HistoryStoring,
        presenter: DictationStatePresenting,
        language: @escaping () -> SpeechRecognitionLanguage,
        successDisplayDuration: Duration = OverlayTiming.successDisplayDuration
    ) {
        self.recorder = recorder
        self.speech = speech
        self.targetCapture = targetCapture
        self.textInserter = textInserter
        self.history = history
        self.presenter = presenter
        self.language = language
        self.successDisplayDuration = successDisplayDuration
    }

    func handleHotkey(_ event: DictationHotkeyEvent, mode: HotkeyMode) {
        if case .keyDown(isAutoRepeat: true) = event { return }
        guard state != .processing, state != .success else { return }

        switch (mode, event, state) {
        case (.toggle, .keyDown, .idle), (.pushToTalk, .keyDown, .idle):
            beginRecording()
        case (.toggle, .keyDown, .recording), (.pushToTalk, .keyUp, .recording):
            finishRecording()
        default:
            break
        }
    }

    func waitForCurrentOperation() async {
        await processingTask?.value
    }

    private func beginRecording() {
        Self.logger.debug("[Dictation] start requested")
        guard speech.status == .ready else {
            lastError = "Speech model is not ready: \(speech.status.displayText)"
            Self.logger.error("[Dictation][ERROR] \(self.lastError ?? "Unknown model error", privacy: .public)")
            insertionTarget = nil
            processingTask = nil
            recorder.cancelRecording()
            publish(.idle)
            return
        }
        do {
            let target = try targetCapture.capture()
            Self.logger.debug("[Dictation] target captured: pid=\(target.processIdentifier, privacy: .public)")
            try recorder.startRecording()
            insertionTarget = target
            lastError = nil
            publish(.recording)
            Self.logger.debug("[Dictation] recording")
        } catch {
            recorder.cancelRecording()
            insertionTarget = nil
            processingTask = nil
            lastError = error.localizedDescription
            Self.logger.error("[Dictation][ERROR] \(error.localizedDescription, privacy: .public)")
            publish(.idle)
        }
    }

    private func finishRecording() {
        guard processingTask == nil, let target = insertionTarget else { return }
        Self.logger.debug("[Dictation] stop requested")
        let recognitionLanguage = language()
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audio = try await recorder.stopRecording()
                publish(.processing)
                Self.logger.debug("[Speech] transcribing \(audio.samples.count, privacy: .public) frames")
                let transcript = try await speech.transcribe(audio, language: recognitionLanguage)
                Self.logger.debug("[Speech] transcription finished")
                history.add(text: transcript)
                do {
                    try await textInserter.insert(transcript, into: target)
                    Self.logger.debug("[Dictation] text inserted")
                    lastError = nil
                    publish(.success)
                    try? await Task.sleep(for: successDisplayDuration)
                } catch {
                    lastError = "Text was recognized and saved to History, but insertion failed: \(error.localizedDescription)"
                    Self.logger.error("[Dictation][ERROR] \(self.lastError ?? "Text insertion failed", privacy: .public)")
                }
            } catch {
                lastError = error.localizedDescription
                Self.logger.error("[Dictation][ERROR] \(error.localizedDescription, privacy: .public)")
            }
            insertionTarget = nil
            processingTask = nil
            publish(.idle)
        }
    }

    private func publish(_ newState: DictationState) {
        state = newState
        presenter.apply(state: newState)
    }
}
