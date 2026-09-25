import Foundation
import Testing
@testable import VoiceInput

@Suite("Overlay style")
struct OverlayStyleTests {
    @Test("Dark appearance is monochrome white on translucent black")
    func darkStyleIsMonochrome() {
        let style = OverlayStyle.resolve(.dark, systemIsDark: false)

        #expect(style.appearance == .dark)
        #expect(style.backgroundWhite == 0)
        #expect(style.foregroundWhite == 1)
        #expect(style.backgroundOpacity == 0.82)
    }

    @Test("Light appearance is monochrome black on translucent white")
    func lightStyleIsInvertedMonochrome() {
        let style = OverlayStyle.resolve(.light, systemIsDark: true)

        #expect(style.appearance == .light)
        #expect(style.backgroundWhite == 1)
        #expect(style.foregroundWhite == 0)
        #expect(style.backgroundOpacity == 0.82)
    }

    @Test("System appearance follows the effective macOS appearance")
    func systemStyleFollowsSystem() {
        #expect(OverlayStyle.resolve(.system, systemIsDark: true).appearance == .dark)
        #expect(OverlayStyle.resolve(.system, systemIsDark: false).appearance == .light)
    }

    @Test("Overlay appearance defaults to System and persists")
    @MainActor
    func appearancePersists() {
        let suite = "VoiceInputTests.OverlayAppearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let initial = AppSettings(defaults: defaults)
        #expect(initial.overlayAppearance == .system)
        initial.overlayAppearance = .light

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.overlayAppearance == .light)
    }

    @Test("Overlay timing uses short reveal, hold, and fade phases")
    func overlayTimingValues() {
        #expect(OverlayTiming.checkRevealDuration == 0.18)
        #expect(OverlayTiming.successHoldDuration == 0.35)
        #expect(OverlayTiming.fadeOutDuration == 0.18)
        #expect(OverlayTiming.successDisplayDuration == .milliseconds(530))
    }
}
