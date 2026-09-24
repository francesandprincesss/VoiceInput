@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import OSLog

struct CapturedAudio: Equatable, Sendable {
    let samples: [Float]
    let sampleRate: Double

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

enum AudioRecorderError: LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case microphoneUnavailable
    case microphonePermissionDenied
    case unsupportedInputFormat
    case tapInstallationFailed(String)
    case noRecordedAudio
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "No recording is in progress."
        case .microphoneUnavailable: "The microphone has no valid native input format."
        case .microphonePermissionDenied: "Microphone access is required. Grant it in VoiceInput Settings."
        case .unsupportedInputFormat: "The microphone input is not Float32 PCM."
        case .tapInstallationFailed(let message): "The microphone tap could not be installed: \(message)"
        case .noRecordedAudio: "No audio was recorded."
        case .engineStartFailed(let message): "The audio engine could not start: \(message)"
        }
    }
}

@MainActor
protocol AudioRecordingService: AnyObject {
    func startRecording() throws
    func stopRecording() async throws -> CapturedAudio
    func cancelRecording()
}

struct AudioInputFormatDescriptor: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: UInt32
    let isFloat32PCM: Bool

    func validate() throws {
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0 else {
            throw AudioRecorderError.microphoneUnavailable
        }
        guard isFloat32PCM else { throw AudioRecorderError.unsupportedInputFormat }
    }
}

struct AudioInputChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double
}

@MainActor
protocol AudioCaptureEngine: AnyObject {
    var inputFormat: AudioInputFormatDescriptor { get }
    var hasInstalledTap: Bool { get }
    func installTap(handler: @escaping @Sendable (AudioInputChunk) -> Void) throws
    func prepare()
    func start() throws
    func stop()
    func removeTapIfInstalled()
}

@MainActor
final class AVAudioCaptureEngine: AudioCaptureEngine {
    private let engine: AVAudioEngine
    private(set) var hasInstalledTap = false

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
    }

    var inputFormat: AudioInputFormatDescriptor {
        let format = engine.inputNode.outputFormat(forBus: 0)
        return AudioInputFormatDescriptor(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            isFloat32PCM: format.commonFormat == .pcmFormatFloat32
        )
    }

    func installTap(handler: @escaping @Sendable (AudioInputChunk) -> Void) throws {
        guard !hasInstalledTap else { throw AudioRecorderError.alreadyRecording }
        let tap = makeNativeAudioTap(handler: handler)
        // A nil format asks AVAudioEngine for the input node's native output format.
        engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil, block: tap)
        hasInstalledTap = true
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    func removeTapIfInstalled() {
        guard hasInstalledTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        hasInstalledTap = false
    }
}

private nonisolated func makeNativeAudioTap(
    handler: @escaping @Sendable (AudioInputChunk) -> Void
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        let frameLength = buffer.frameLength
        guard frameLength > 0,
              frameLength <= buffer.frameCapacity,
              buffer.format.channelCount > 0,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData else { return }

        let count = Int(frameLength)
        let firstChannel = channels[0]
        let samples = Array(UnsafeBufferPointer(start: firstChannel, count: count))
        handler(AudioInputChunk(samples: samples, sampleRate: buffer.format.sampleRate))
    }
}

private nonisolated func makeChunkHandler(
    accumulator: SampleAccumulator,
    levelMonitor: AudioLevelMonitor
) -> @Sendable (AudioInputChunk) -> Void {
    { chunk in
        guard !chunk.samples.isEmpty, chunk.sampleRate.isFinite, chunk.sampleRate > 0 else { return }
        accumulator.append(chunk.samples, sampleRate: chunk.sampleRate)
        levelMonitor.consume(chunk.samples)
    }
}

final class SampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [[Float]] = []
    private var rate: Double = 0

    func reset(sampleRate: Double) {
        lock.withLock {
            chunks.removeAll(keepingCapacity: true)
            rate = sampleRate
        }
    }

    func append(_ samples: [Float], sampleRate: Double) {
        lock.withLock {
            if rate == 0 { rate = sampleRate }
            guard abs(rate - sampleRate) < 0.5 else { return }
            chunks.append(samples)
        }
    }

    func take() -> (samples: [Float], sampleRate: Double) {
        lock.withLock {
            let result = chunks.flatMap { $0 }
            let capturedRate = rate
            chunks.removeAll(keepingCapacity: false)
            rate = 0
            return (result, capturedRate)
        }
    }
}

@MainActor
final class AudioRecorder: AudioRecordingService {
    private enum State {
        case idle
        case tapInstalled
        case recording
    }

    private static let logger = Logger(subsystem: "com.local.voiceinput", category: "Audio")

    private let captureEngine: AudioCaptureEngine
    private let levelMonitor: AudioLevelMonitor
    private let microphonePermissionGranted: () -> Bool
    private let accumulator = SampleAccumulator()
    private var state: State = .idle

    convenience init(levelMonitor: AudioLevelMonitor) {
        self.init(
            captureEngine: AVAudioCaptureEngine(),
            levelMonitor: levelMonitor,
            microphonePermissionGranted: {
                AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
        )
    }

    init(
        captureEngine: AudioCaptureEngine,
        levelMonitor: AudioLevelMonitor,
        microphonePermissionGranted: @escaping () -> Bool
    ) {
        self.captureEngine = captureEngine
        self.levelMonitor = levelMonitor
        self.microphonePermissionGranted = microphonePermissionGranted
    }

    func startRecording() throws {
        guard state == .idle, !captureEngine.hasInstalledTap else {
            Self.logger.error("[Audio][ERROR] Duplicate startRecording request")
            throw AudioRecorderError.alreadyRecording
        }
        guard microphonePermissionGranted() else {
            Self.logger.error("[Audio][ERROR] Microphone permission is missing")
            throw AudioRecorderError.microphonePermissionDenied
        }

        let format = captureEngine.inputFormat
        Self.logger.debug(
            "[Audio] input format: sampleRate=\(format.sampleRate, privacy: .public), channels=\(format.channelCount, privacy: .public)"
        )
        do {
            try format.validate()
        } catch {
            Self.logger.error("[Audio][ERROR] \(error.localizedDescription, privacy: .public)")
            throw error
        }
        accumulator.reset(sampleRate: format.sampleRate)

        do {
            Self.logger.debug("[Audio] installing tap")
            try captureEngine.installTap(
                handler: makeChunkHandler(accumulator: accumulator, levelMonitor: levelMonitor)
            )
            state = .tapInstalled
            Self.logger.debug("[Audio] engine preparing")
            captureEngine.prepare()
            try captureEngine.start()
            state = .recording
            Self.logger.debug("[Audio] engine started")
        } catch {
            let tapWasInstalled = captureEngine.hasInstalledTap
            cleanupCapture()
            Self.logger.error("[Audio][ERROR] \(error.localizedDescription, privacy: .public)")
            if let recorderError = error as? AudioRecorderError { throw recorderError }
            if !tapWasInstalled {
                throw AudioRecorderError.tapInstallationFailed(error.localizedDescription)
            }
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> CapturedAudio {
        guard state == .recording else { throw AudioRecorderError.notRecording }
        Self.logger.debug("[Audio] stopping")
        captureEngine.removeTapIfInstalled()
        captureEngine.stop()
        state = .idle

        let captured = accumulator.take()
        Self.logger.debug("[Audio] captured \(captured.samples.count, privacy: .public) frames")
        guard !captured.samples.isEmpty, captured.sampleRate > 0 else {
            Self.logger.error("[Audio][ERROR] No audio was recorded")
            throw AudioRecorderError.noRecordedAudio
        }

        Self.logger.debug("[Audio] resampling")
        let samples: [Float]
        do {
            samples = try await Task.detached(priority: .userInitiated) {
                try AudioConverter().resample(captured.samples, from: captured.sampleRate)
            }.value
        } catch {
            Self.logger.error("[Audio][ERROR] Resampling failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard !samples.isEmpty else { throw AudioRecorderError.noRecordedAudio }
        return CapturedAudio(samples: samples, sampleRate: 16_000)
    }

    func cancelRecording() {
        guard state != .idle || captureEngine.hasInstalledTap else { return }
        cleanupCapture()
    }

    private func cleanupCapture() {
        captureEngine.removeTapIfInstalled()
        captureEngine.stop()
        state = .idle
        _ = accumulator.take()
    }
}
