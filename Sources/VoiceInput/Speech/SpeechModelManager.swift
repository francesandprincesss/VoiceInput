import Foundation

@MainActor
final class SpeechModelManager: ObservableObject, SpeechRecognizer {
    @Published private(set) var status: SpeechModelStatus = .notLoaded

    private let recognizer: any SpeechRecognitionBackend
    private var preparationTask: Task<Void, Never>?

    init(recognizer: any SpeechRecognitionBackend = ParakeetSpeechRecognizer()) {
        self.recognizer = recognizer
    }

    func prepare() {
        guard preparationTask == nil, status != .ready else { return }
        let recognizer = recognizer
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await recognizer.prepare { [self] update in
                    Task { @MainActor [self] in self.status = update }
                }
            } catch {
                self.status = .failed(error.localizedDescription)
            }
            self.preparationTask = nil
        }
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: SpeechRecognitionLanguage
    ) async throws -> String {
        guard status == .ready else { throw SpeechRecognizerError.modelNotReady }
        return try await recognizer.transcribe(audio, language: language)
    }
}
