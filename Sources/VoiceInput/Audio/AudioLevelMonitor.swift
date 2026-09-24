import AVFoundation
import Foundation

final class AudioLevelMonitor: AudioLevelProviding, @unchecked Sendable {
    private let meter = LockedLevel()
    private var displayedLevel: Float = 0
    private var timer: Timer?
    private var callback: (@MainActor @Sendable (Float) -> Void)?

    nonisolated func consume(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        for value in samples {
            sum += value * value
        }
        let rms = sqrt(sum / Float(samples.count))
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (decibels + 55) / 45))
        meter.set(normalized)
    }

    @MainActor
    func start(onLevel: @escaping @MainActor @Sendable (Float) -> Void) {
        stop()
        callback = onLevel
        displayedLevel = 0
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1.0 / 60.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor
    func stop() {
        timer?.invalidate()
        timer = nil
        callback = nil
        displayedLevel = 0
        meter.set(0)
    }

    @MainActor
    private func tick() {
        let target = meter.get()
        let factor: Float = target > displayedLevel ? 0.42 : 0.16
        displayedLevel += (target - displayedLevel) * factor
        callback?(displayedLevel)
    }
}

private final class LockedLevel: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func set(_ newValue: Float) { lock.withLock { value = newValue } }
    func get() -> Float { lock.withLock { value } }
}
