import Foundation

@MainActor
protocol AudioLevelProviding: AnyObject {
    func start(onLevel: @escaping @MainActor @Sendable (Float) -> Void)
    func stop()
}

@MainActor
final class MockAudioLevelProvider: AudioLevelProviding {
    private var timer: Timer?
    private var phase: Double = 0

    func start(onLevel: @escaping @MainActor @Sendable (Float) -> Void) {
        stop()
        phase = 0
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.phase += 0.19
                let primary = (sin(self.phase) + 1) * 0.5
                let secondary = (sin(self.phase * 0.43 + 1.7) + 1) * 0.5
                onLevel(Float(0.12 + 0.70 * primary * secondary))
            }
        }
        timer.tolerance = 1.0 / 48.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
