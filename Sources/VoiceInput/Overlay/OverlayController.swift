import AppKit

@MainActor
final class OverlayController: DictationStatePresenting {
    private static let baseSize = NSSize(width: 64, height: 38)
    private static let visualScale: CGFloat = 1.5
    private static let animateInDuration: TimeInterval = 0.32
    private static let animateOutDuration: TimeInterval = 0.23

    private let panel: OverlayPanel
    private let overlayView: OverlayView
    private let audioLevelProvider: AudioLevelProviding
    private let panelSize = NSSize(
        width: baseSize.width * visualScale,
        height: baseSize.height * visualScale
    )
    private let bottomInset: CGFloat = 42

    private var motionTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var revealStartedAt: TimeInterval?
    private var revealFrom: CGFloat = 0
    private var revealTo: CGFloat = 1
    private var revealDuration = animateInDuration
    private var hideWhenRevealFinishes = false

    init(audioLevelProvider: AudioLevelProviding) {
        self.audioLevelProvider = audioLevelProvider
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: panelSize))
        panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func apply(state: DictationState) {
        switch state {
        case .idle:
            audioLevelProvider.stop()
            hide()
        case .recording:
            overlayView.mode = .recording
            overlayView.level = 0
            show()
            audioLevelProvider.start { [weak self] level in
                self?.overlayView.level = level
            }
        case .processing:
            audioLevelProvider.stop()
            overlayView.level = 0
            overlayView.mode = .processing
            ensureVisible()
        case .success:
            audioLevelProvider.stop()
            overlayView.level = 0
            overlayView.mode = .success
            ensureVisible()
        }
    }

    private func show() {
        positionPanel()
        hideWhenRevealFinishes = false
        overlayView.revealProgress = 0
        panel.orderFrontRegardless()
        startReveal(from: 0, to: 1, duration: Self.animateInDuration)
    }

    private func ensureVisible() {
        if !panel.isVisible {
            show()
        } else {
            hideWhenRevealFinishes = false
            overlayView.revealProgress = 1
            startMotion()
        }
    }

    private func hide() {
        guard panel.isVisible else {
            stopMotion()
            return
        }
        hideWhenRevealFinishes = true
        startReveal(
            from: overlayView.revealProgress,
            to: 0,
            duration: Self.animateOutDuration
        )
    }

    private func configurePanel() {
        overlayView.autoresizingMask = [.width, .height]
        panel.contentView = overlayView
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + bottomInset
        ))
    }

    private func startReveal(from: CGFloat, to: CGFloat, duration: TimeInterval) {
        revealFrom = max(0, min(1, from))
        revealTo = max(0, min(1, to))
        revealDuration = max(1.0 / 60.0, duration * Double(abs(revealTo - revealFrom)))
        revealStartedAt = ProcessInfo.processInfo.systemUptime
        startMotion()
    }

    private func startMotion() {
        guard motionTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        timer.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func stopMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
        revealStartedAt = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0.001, min(0.05, now - lastTick))
        lastTick = now
        let speed: CGFloat = overlayView.mode == .recording
            ? 16.96 + CGFloat(overlayView.level) * 10.08
            : 10.2
        overlayView.phase += CGFloat(delta) * speed

        guard let revealStartedAt else { return }
        let progress = min(1, max(0, (now - revealStartedAt) / revealDuration))
        overlayView.revealProgress = revealFrom
            + (revealTo - revealFrom) * CGFloat(progress)
        if progress >= 1 {
            self.revealStartedAt = nil
            if hideWhenRevealFinishes {
                panel.orderOut(nil)
                overlayView.revealProgress = 1
                hideWhenRevealFinishes = false
                stopMotion()
            }
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
