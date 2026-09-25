import AppKit
import Foundation

enum OverlayAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

enum OverlayResolvedAppearance: Equatable, Sendable {
    case dark
    case light
}

struct OverlayStyle: Equatable, Sendable {
    let appearance: OverlayResolvedAppearance
    let backgroundWhite: CGFloat
    let backgroundOpacity: CGFloat
    let foregroundWhite: CGFloat

    static func resolve(
        _ appearance: OverlayAppearance,
        systemIsDark: Bool
    ) -> OverlayStyle {
        let resolved: OverlayResolvedAppearance
        switch appearance {
        case .system: resolved = systemIsDark ? .dark : .light
        case .dark: resolved = .dark
        case .light: resolved = .light
        }
        switch resolved {
        case .dark:
            return OverlayStyle(
                appearance: .dark,
                backgroundWhite: 0,
                backgroundOpacity: OverlayMetrics.backgroundOpacity,
                foregroundWhite: 1
            )
        case .light:
            return OverlayStyle(
                appearance: .light,
                backgroundWhite: 1,
                backgroundOpacity: OverlayMetrics.backgroundOpacity,
                foregroundWhite: 0
            )
        }
    }

    var backgroundColor: NSColor {
        NSColor(calibratedWhite: backgroundWhite, alpha: backgroundOpacity)
    }

    var foregroundColor: NSColor {
        NSColor(calibratedWhite: foregroundWhite, alpha: 1)
    }
}

enum OverlayMetrics {
    static let size = NSSize(width: 114, height: 42)
    static let contentInset: CGFloat = 3
    static let cornerRadius: CGFloat = 18
    static let bottomInset: CGFloat = 42
    static let backgroundOpacity: CGFloat = 0.82
    static let borderOpacity: CGFloat = 0.14
    static let barCount = 8
    static let barWidth: CGFloat = 2.2
    static let barGap: CGFloat = 3.0
    static let minimumBarHeight: CGFloat = 3
    static let maximumBarHeight: CGFloat = 20
}

enum OverlayTiming {
    static let revealDuration: TimeInterval = 0.24
    static let processingTransitionDuration: TimeInterval = 0.18
    static let checkRevealDuration: TimeInterval = 0.18
    static let successHoldDuration: TimeInterval = 0.35
    static let fadeOutDuration: TimeInterval = 0.18
    static let successDisplayDuration: Duration = .milliseconds(530)
}
