import FluidAudio
import Foundation

enum SpeechRecognizerError: LocalizedError {
    case modelNotReady
    case noAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .modelNotReady: "The speech model is not ready."
        case .noAudio: "There is no recorded audio to transcribe."
        case .emptyTranscript: "No speech was recognized."
        }
    }
}

actor ParakeetSpeechRecognizer: SpeechRecognitionBackend {
    private var manager: AsrManager?

    func prepare(status: @escaping @Sendable (SpeechModelStatus) -> Void) async throws {
        if manager != nil {
            status(.ready)
            return
        }

        let cache = AsrModels.defaultCacheDirectory(for: .v3)
        let isCached = AsrModels.modelsExist(at: cache, version: .v3, encoderPrecision: .int8)
        status(isCached ? .loading : .downloading(progress: nil))

        let models = try await AsrModels.downloadAndLoad(
            version: .v3,
            encoderPrecision: .int8
        ) { progress in
            switch progress.phase {
            case .listing, .downloading:
                status(.downloading(progress: progress.fractionCompleted))
            case .compiling:
                status(.loading)
            }
        }
        manager = AsrManager(config: .default, models: models)
        status(.ready)
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: SpeechRecognitionLanguage
    ) async throws -> String {
        guard !audio.samples.isEmpty else { throw SpeechRecognizerError.noAudio }
        guard let manager else { throw SpeechRecognizerError.modelNotReady }
        let layers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: layers)
        let result = try await manager.transcribe(
            audio.samples,
            decoderState: &decoderState,
            language: language.fluidAudioLanguage
        )
        let text = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else { throw SpeechRecognizerError.emptyTranscript }
        return text
    }
}

private extension SpeechRecognitionLanguage {
    var fluidAudioLanguage: Language? {
        switch self {
        case .automatic: nil
        case .russian: .russian
        case .english: .english
        }
    }
}
