import Foundation
import Testing
@testable import VoiceInput

@Suite("Audio recorder safety", .serialized)
@MainActor
struct AudioRecorderTests {
    @Test("Invalid microphone format returns an error without installing a tap")
    func invalidFormat() {
        let engine = CaptureEngineMock(
            format: AudioInputFormatDescriptor(sampleRate: 0, channelCount: 0, isFloat32PCM: true)
        )
        let recorder = makeRecorder(engine: engine)

        do {
            try recorder.startRecording()
            Issue.record("Expected microphoneUnavailable")
        } catch let error as AudioRecorderError {
            #expect(error == .microphoneUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(engine.installCount == 0)
        #expect(!engine.hasInstalledTap)
    }

    @Test("Engine start failure removes the installed tap")
    func engineStartFailureCleansUp() {
        let engine = CaptureEngineMock.valid()
        engine.startError = EngineFailure.start
        let recorder = makeRecorder(engine: engine)

        #expect(throws: AudioRecorderError.self) {
            try recorder.startRecording()
        }
        #expect(!engine.hasInstalledTap)
        #expect(engine.stopCount == 1)
    }

    @Test("Duplicate startRecording is rejected and does not install another tap")
    func duplicateStart() throws {
        let engine = CaptureEngineMock.valid()
        let recorder = makeRecorder(engine: engine)
        try recorder.startRecording()

        do {
            try recorder.startRecording()
            Issue.record("Expected alreadyRecording")
        } catch let error as AudioRecorderError {
            #expect(error == .alreadyRecording)
        }
        #expect(engine.installCount == 1)
        recorder.cancelRecording()
    }

    @Test("Stopping before a successful start returns a safe error")
    func stopWithoutStart() async {
        let recorder = makeRecorder(engine: .valid())
        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected notRecording")
        } catch let error as AudioRecorderError {
            #expect(error == .notRecording)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("An empty capture returns noRecordedAudio")
    func emptyCapture() async throws {
        let engine = CaptureEngineMock.valid()
        let recorder = makeRecorder(engine: engine)
        try recorder.startRecording()

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected noRecordedAudio")
        } catch let error as AudioRecorderError {
            #expect(error == .noRecordedAudio)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!engine.hasInstalledTap)
    }

    @Test("Realtime callback is callable away from MainActor")
    func callbackIsNonisolated() async throws {
        let engine = CaptureEngineMock.valid()
        let recorder = makeRecorder(engine: engine)
        try recorder.startRecording()
        let callback = try #require(engine.handler)

        await Task.detached {
            callback(AudioInputChunk(samples: Array(repeating: 0.1, count: 4_800), sampleRate: 48_000))
        }.value

        let audio = try await recorder.stopRecording()
        #expect(!audio.samples.isEmpty)
    }

    private func makeRecorder(engine: CaptureEngineMock) -> AudioRecorder {
        AudioRecorder(
            captureEngine: engine,
            levelMonitor: AudioLevelMonitor(),
            microphonePermissionGranted: { true }
        )
    }
}

@MainActor
private final class CaptureEngineMock: AudioCaptureEngine {
    let inputFormat: AudioInputFormatDescriptor
    private(set) var hasInstalledTap = false
    private(set) var installCount = 0
    private(set) var stopCount = 0
    var startError: Error?
    var handler: (@Sendable (AudioInputChunk) -> Void)?

    init(format: AudioInputFormatDescriptor) {
        inputFormat = format
    }

    static func valid() -> CaptureEngineMock {
        CaptureEngineMock(
            format: AudioInputFormatDescriptor(
                sampleRate: 48_000,
                channelCount: 1,
                isFloat32PCM: true
            )
        )
    }

    func installTap(handler: @escaping @Sendable (AudioInputChunk) -> Void) throws {
        guard !hasInstalledTap else { throw AudioRecorderError.alreadyRecording }
        installCount += 1
        hasInstalledTap = true
        self.handler = handler
    }

    func prepare() {}

    func start() throws {
        if let startError { throw startError }
    }

    func stop() { stopCount += 1 }

    func removeTapIfInstalled() {
        guard hasInstalledTap else { return }
        hasInstalledTap = false
        handler = nil
    }
}

private enum EngineFailure: Error {
    case start
}
