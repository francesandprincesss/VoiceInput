import Foundation

@MainActor
final class SpeechRecognizerRouter: ObservableObject, SpeechRecognizer {
    @Published private(set) var mode: SpeechProcessingMode

    private let localRecognizer: SpeechRecognizer
    private let apiRecognizer: SpeechRecognizer

    var status: SpeechModelStatus { activeRecognizer.status }

    init(
        mode: SpeechProcessingMode,
        localRecognizer: SpeechRecognizer,
        apiRecognizer: SpeechRecognizer
    ) {
        self.mode = mode
        self.localRecognizer = localRecognizer
        self.apiRecognizer = apiRecognizer
    }

    func setMode(_ newMode: SpeechProcessingMode) {
        guard mode != newMode else { return }
        mode = newMode
        activeRecognizer.prepare()
    }

    func prepare() {
        activeRecognizer.prepare()
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: SpeechRecognitionLanguage
    ) async throws -> String {
        try await activeRecognizer.transcribe(audio, language: language)
    }

    private var activeRecognizer: SpeechRecognizer {
        switch mode {
        case .local: localRecognizer
        case .api: apiRecognizer
        }
    }
}
