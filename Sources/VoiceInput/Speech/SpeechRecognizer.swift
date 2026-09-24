import Foundation

enum SpeechRecognitionLanguage: Sendable {
    case automatic
    case russian
    case english
}

enum SpeechModelStatus: Equatable, Sendable {
    case notLoaded
    case downloading(progress: Double?)
    case loading
    case ready
    case failed(String)

    var displayText: String {
        switch self {
        case .notLoaded: "Not loaded"
        case .downloading(let progress):
            if let progress { "Downloading \(Int(progress * 100))%" } else { "Downloading" }
        case .loading: "Loading"
        case .ready: "Ready"
        case .failed(let message): "Error — \(message)"
        }
    }
}

protocol SpeechRecognitionBackend: Sendable {
    func prepare(status: @escaping @Sendable (SpeechModelStatus) -> Void) async throws
    func transcribe(_ audio: CapturedAudio, language: SpeechRecognitionLanguage) async throws -> String
}

@MainActor
protocol SpeechRecognizer: AnyObject {
    var status: SpeechModelStatus { get }
    func prepare()
    func transcribe(_ audio: CapturedAudio, language: SpeechRecognitionLanguage) async throws -> String
}
