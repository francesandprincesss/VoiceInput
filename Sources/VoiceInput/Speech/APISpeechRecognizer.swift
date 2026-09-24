import Foundation

struct APIConfiguration: Equatable, Sendable {
    var providerIdentifier: String?
    var credentialAccount: String?

    var isConfigured: Bool {
        guard let providerIdentifier else { return false }
        return !providerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let unconfigured = APIConfiguration()
}

enum APISpeechRecognizerError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: "API provider is not configured."
        }
    }
}

@MainActor
final class APISpeechRecognizer: SpeechRecognizer {
    private(set) var status: SpeechModelStatus
    private let configuration: APIConfiguration

    init(configuration: APIConfiguration = .unconfigured) {
        self.configuration = configuration
        status = configuration.isConfigured
            ? .notLoaded
            : .failed(APISpeechRecognizerError.notConfigured.localizedDescription)
    }

    func prepare() {
        guard configuration.isConfigured else {
            status = .failed(APISpeechRecognizerError.notConfigured.localizedDescription)
            return
        }
        // A concrete provider will own preparation in a later stage.
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: SpeechRecognitionLanguage
    ) async throws -> String {
        throw APISpeechRecognizerError.notConfigured
    }
}
