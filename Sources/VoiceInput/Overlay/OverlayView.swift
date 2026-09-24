import AppKit

// Visual implementation adapted from SuperDictate's RecordingHUDView:
// https://github.com/shlgd/SuperDictate/blob/4166fbdd6e7ea86a62d04d1085c4dfe819095b97/swift/Sources/Parakey/main.swift
// SuperDictate/Parakey is MIT licensed. See THIRD_PARTY_NOTICES.md.

final class OverlayView: NSView {
    enum Mode {
        case recording
        case processing
        case success
    }

    var mode: Mode = .recording {
        didSet {
            if oldValue != mode {
                modeChangedAt = ProcessInfo.processInfo.systemUptime
                needsDisplay = true
            }
        }
    }
    var level: Float = 0 { didSet { needsDisplay = true } }
    var phase: CGFloat = 0 { didSet { needsDisplay = true } }
    var revealProgress: CGFloat = 1 { didSet { needsDisplay = true } }

    private let visualScale: CGFloat = 1.5
    private let recordingColor = NSColor.systemRed
    private let processingColor = NSColor(
        calibratedRed: 0.0,
        green: 0.44,
        blue: 1.0,
        alpha: 1
    )
    private let successColor = NSColor.systemGreen
    private var modeChangedAt = ProcessInfo.processInfo.systemUptime

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawOverlay()
    }

    private func drawOverlay() {
        let reveal = max(0, min(1, revealProgress))
        guard reveal > 0.001 else { return }

        let audio = pow(CGFloat(max(0, min(1, level))), 0.82)
        let settlePeak: CGFloat = 0.68
        let settleOvershoot: CGFloat = 0.10
        let grow: CGFloat
        if reveal <= settlePeak {
            grow = (1 + settleOvershoot) * smootherstep(0, settlePeak, reveal)
        } else {
            grow = (1 + settleOvershoot)
                - settleOvershoot * smootherstep(settlePeak, 1, reveal)
        }

        let capsuleAlpha = smootherstep(0, 0.34, reveal)
        let contentAlpha = smootherstep(0.16, 0.78, reveal)
        let startDiameter = 6 * visualScale
        let finalRect = bounds.insetBy(dx: 4 * visualScale, dy: 4 * visualScale)
        let breathingReady = smootherstep(0.82, 1, reveal)
        let idleBreath = 0.0032 + 0.0018 * sin(phase * 0.31)
        let voiceBreath = audio * (0.014 + 0.008 * ((sin(phase * 0.87) + 1) / 2))
        let successPulse: CGFloat = mode == .success
            ? 0.012 * max(0, sin(phase * 1.3))
            : 0
        let liveScale = 1 + (idleBreath + voiceBreath + successPulse) * breathingReady
        let width = (startDiameter + (finalRect.width - startDiameter) * grow) * liveScale
        let height = (startDiameter + (finalRect.height - startDiameter) * grow) * liveScale
        let capsuleRect = NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
        let capsule = NSBezierPath(
            roundedRect: capsuleRect,
            xRadius: capsuleRect.height / 2,
            yRadius: capsuleRect.height / 2
        )
        NSColor(calibratedWhite: 0, alpha: 0.96 * capsuleAlpha).setFill()
        capsule.fill()
        NSColor(calibratedWhite: 0.22, alpha: 0.26 * capsuleAlpha).setStroke()
        capsule.lineWidth = visualScale
        capsule.stroke()

        guard contentAlpha > 0.001 else { return }
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        capsule.addClip()
        context.setAlpha(contentAlpha)
        defer { NSGraphicsContext.restoreGraphicsState() }

        switch mode {
        case .recording:
            drawRecordingBars(in: capsuleRect, audio: audio)
        case .processing:
            drawProcessingBars(in: capsuleRect)
        case .success:
            drawSuccess(in: capsuleRect)
        }
    }

    private func drawRecordingBars(in capsuleRect: NSRect, audio: CGFloat) {
        let barCount = 8
        let barWidth = 2.05 * visualScale
        let barGap = 2.55 * visualScale
        let minHeight = 3.0 * visualScale
        let maxHeight = min(capsuleRect.height * 0.58, 13.2 * visualScale)
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = bounds.midX - totalWidth / 2
        let centerIndex = CGFloat(barCount - 1) / 2

        for index in 0..<barCount {
            let i = CGFloat(index)
            let normalized = (i - centerIndex) / max(centerIndex, 1)
            let envelope = pow(max(0, cos(normalized * .pi / 2)), 0.62)
            let traveling = (sin(phase * 1.02 - normalized * 2.85) + 1) / 2
            let counter = (sin(phase * 1.57 + i * 1.17) + 1) / 2
            let variance = (sin(phase * 0.23 + i * 2.11) + 1) / 2
            let voiceMotion = audio * (0.22 + 0.78 * envelope)
                * (0.18 + 0.42 * traveling + 0.14 * counter)
                * (0.72 + 0.28 * variance)
            let activity = min(
                0.88,
                0.14 + 0.075 * traveling + 0.055 * counter * envelope + voiceMotion
            )
            drawBar(
                x: startX + i * (barWidth + barGap),
                height: minHeight + (maxHeight - minHeight) * activity,
                width: barWidth,
                color: recordingColor,
                glow: 0.07 + 0.10 * activity,
                alpha: 0.74 + 0.26 * activity
            )
        }
    }

    private func drawProcessingBars(in capsuleRect: NSRect) {
        let barCount = 8
        let barWidth = 2.05 * visualScale
        let barGap = 2.55 * visualScale
        let minHeight = 3.2 * visualScale
        let maxHeight = min(capsuleRect.height * 0.60, 14.6 * visualScale)
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = capsuleRect.midX - totalWidth / 2
        let centerIndex = CGFloat(barCount - 1) / 2
        let age = CGFloat(max(0, ProcessInfo.processInfo.systemUptime - modeChangedAt))
        let resolveProgress = min(1, age / 0.20)
        let loopPhase = max(0, age - 0.20)

        for index in 0..<barCount {
            let i = CGFloat(index)
            let normalized = (i - centerIndex) / max(centerIndex, 1)
            let envelope = pow(max(0, cos(normalized * .pi / 2)), 0.62)
            let barProgress = i / CGFloat(max(1, barCount - 1))
            let conversion = smoothstep(barProgress - 0.34, barProgress + 0.08, resolveProgress)
            let front = max(0, 1 - abs(resolveProgress - barProgress) / 0.18)
                * (1 - smoothstep(0.82, 1, resolveProgress))
            let reverseHead = 1 - (loopPhase * 3.8).truncatingRemainder(dividingBy: 1)
            let reversePulse = max(0, 1 - abs(reverseHead - barProgress) / 0.24)
            let loopWave = (sin(loopPhase * 6.2 + i * 0.56) + 1) / 2
            let activity = min(
                0.94,
                0.15 + 0.24 * envelope
                    + (1 - conversion) * (0.16 + 0.12 * envelope)
                    + conversion * (0.14 * loopWave + 0.34 * reversePulse)
                    + front * (0.48 + 0.30 * envelope)
            )
            let color = recordingColor.blended(withFraction: conversion, of: processingColor)
                ?? processingColor
            drawBar(
                x: startX + i * (barWidth + barGap),
                height: minHeight + (maxHeight - minHeight) * activity,
                width: barWidth,
                color: color,
                glow: 0.055 + 0.12 * front + 0.10 * reversePulse,
                alpha: 0.58 + 0.26 * front + 0.20 * reversePulse + 0.14 * conversion
            )
        }
    }

    private func drawBar(
        x: CGFloat,
        height: CGFloat,
        width: CGFloat,
        color: NSColor,
        glow: CGFloat,
        alpha: CGFloat
    ) {
        let rect = NSRect(
            x: x,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
        let glowRect = rect.insetBy(dx: -1.2 * visualScale, dy: -1.2 * visualScale)
        color.withAlphaComponent(glow).setFill()
        NSBezierPath(
            roundedRect: glowRect,
            xRadius: glowRect.width / 2,
            yRadius: glowRect.width / 2
        ).fill()
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: width / 2,
            yRadius: width / 2
        ).fill()
    }

    private func drawSuccess(in capsuleRect: NSRect) {
        let age = CGFloat(max(0, ProcessInfo.processInfo.systemUptime - modeChangedAt))
        let progress = smootherstep(0, 0.28, age)
        let path = NSBezierPath()
        let start = NSPoint(x: capsuleRect.midX - 8 * visualScale, y: capsuleRect.midY)
        let middle = NSPoint(
            x: capsuleRect.midX - 2 * visualScale,
            y: capsuleRect.midY + 6 * visualScale
        )
        let end = NSPoint(
            x: capsuleRect.midX + 10 * visualScale,
            y: capsuleRect.midY - 7 * visualScale
        )
        path.move(to: start)
        if progress < 0.45 {
            let t = progress / 0.45
            path.line(to: NSPoint(
                x: start.x + (middle.x - start.x) * t,
                y: start.y + (middle.y - start.y) * t
            ))
        } else {
            path.line(to: middle)
            let t = (progress - 0.45) / 0.55
            path.line(to: NSPoint(
                x: middle.x + (end.x - middle.x) * t,
                y: middle.y + (end.y - middle.y) * t
            ))
        }
        successColor.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2.4 * visualScale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return value >= edge1 ? 1 : 0 }
        let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return value >= edge1 ? 1 : 0 }
        let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}
