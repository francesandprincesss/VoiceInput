import Foundation
import Testing
@testable import VoiceInput

@Suite("Speech recognizer routing", .serialized)
@MainActor
struct SpeechRecognizerRouterTests {
    @Test("Default processing mode is local")
    func defaultModeIsLocal() {
        let suite = "VoiceInputTests.SpeechMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.speechProcessingMode == .local)
    }

    @Test("Local mode resolves the injected Parakeet route only")
    func localModeUsesOnlyLocalRecognizer() async throws {
        let local = CountingRecognizer(result: "local")
        let api = CountingRecognizer(result: "api")
        let router = SpeechRecognizerRouter(
            mode: .local,
            localRecognizer: local,
            apiRecognizer: api
        )

        router.prepare()
        let result = try await router.transcribe(sampleAudio, language: .automatic)
        #expect(result == "local")
        #expect(local.prepareCount == 1)
        #expect(local.transcribeCount == 1)
        #expect(api.prepareCount == 0)
        #expect(api.transcribeCount == 0)
    }

    @Test("API mode without configuration returns notConfigured and never invokes local")
    func unconfiguredAPI() async {
        let local = CountingRecognizer(result: "local")
        let api = APISpeechRecognizer()
        let router = SpeechRecognizerRouter(
            mode: .api,
            localRecognizer: local,
            apiRecognizer: api
        )

        router.prepare()
        do {
            _ = try await router.transcribe(sampleAudio, language: .automatic)
            Issue.record("Expected APISpeechRecognizerError.notConfigured")
        } catch let error as APISpeechRecognizerError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(local.prepareCount == 0)
        #expect(local.transcribeCount == 0)
    }

    @Test("Switching modes changes the route without mixing recognizers")
    func switchingModes() async throws {
        let local = CountingRecognizer(result: "local")
        let api = CountingRecognizer(result: "api")
        let router = SpeechRecognizerRouter(
            mode: .local,
            localRecognizer: local,
            apiRecognizer: api
        )

        let localResult = try await router.transcribe(sampleAudio, language: .automatic)
        router.setMode(.api)
        let apiResult = try await router.transcribe(sampleAudio, language: .english)

        #expect(localResult == "local")
        #expect(apiResult == "api")
        #expect(local.transcribeCount == 1)
        #expect(api.transcribeCount == 1)
    }

    private var sampleAudio: CapturedAudio {
        CapturedAudio(samples: [0.1, 0.2], sampleRate: 16_000)
    }
}

@MainActor
private final class CountingRecognizer: SpeechRecognizer {
    var status: SpeechModelStatus = .ready
    private(set) var prepareCount = 0
    private(set) var transcribeCount = 0
    private let result: String

    init(result: String) {
        self.result = result
    }

    func prepare() { prepareCount += 1 }

    func transcribe(
        _ audio: CapturedAudio,
        language: SpeechRecognitionLanguage
    ) async throws -> String {
        transcribeCount += 1
        return result
    }
}
