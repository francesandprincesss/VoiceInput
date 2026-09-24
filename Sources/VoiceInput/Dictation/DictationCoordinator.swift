import Foundation

struct DictationSimulationTiming: Sendable {
    let processingDuration: TimeInterval
    let successDuration: TimeInterval

    static let development = DictationSimulationTiming(
        processingDuration: 0.75,
        successDuration: 0.55
    )
}

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle

    private var machine = DictationStateMachine()
    private let overlayController: OverlayController
    private let simulationTiming: DictationSimulationTiming
    private let simulatesProcessing: Bool
    private var simulationTask: Task<Void, Never>?

    init(
        overlayController: OverlayController,
        simulationTiming: DictationSimulationTiming = .development,
        simulatesProcessing: Bool = true
    ) {
        self.overlayController = overlayController
        self.simulationTiming = simulationTiming
        self.simulatesProcessing = simulatesProcessing
    }

    func handleHotkey(_ event: DictationHotkeyEvent, mode: HotkeyMode) {
        guard machine.handle(event, mode: mode) else { return }
        publishState()

        if state == .processing, simulatesProcessing {
            scheduleSimulatedCompletion()
        }
    }

    func processingDidFinish() {
        simulationTask?.cancel()
        guard machine.processingDidFinish() else { return }
        publishState()
        scheduleSuccessDismissal()
    }

    private func scheduleSimulatedCompletion() {
        simulationTask?.cancel()
        let delay = simulationTiming.processingDuration
        simulationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(delay))
            guard !Task.isCancelled else { return }
            self?.processingDidFinish()
        }
    }

    private func scheduleSuccessDismissal() {
        let delay = simulationTiming.successDuration
        simulationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard self.machine.successDidFinish() else { return }
            self.publishState()
        }
    }

    private func publishState() {
        state = machine.state
        overlayController.apply(state: state)
    }

    nonisolated private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
