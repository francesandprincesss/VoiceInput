# VoiceInput

Minimal native menu bar application for macOS on Apple Silicon. This first-stage
foundation contains settings, an in-memory history model, and a non-activating
floating overlay. It intentionally contains no microphone capture, global hotkey,
or speech recognition implementation.

## Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Swift 6 toolchain

## Build and run

```sh
swift build
swift run
```

After launch, use the waveform icon in the macOS menu bar. The app does not open
a regular window automatically.

## Structure

- `App` — application lifecycle, menu bar, and window coordination
- `Settings` — persisted recording mode and language preferences
- `History` — history model, store, and empty-state window
- `Overlay` — non-activating AppKit panel and SwiftUI indicator
- `Hotkey` — recording-mode model (no global hotkey implementation yet)
