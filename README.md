# VoiceInput

Minimal native menu bar application for macOS on Apple Silicon. It includes a
recordable global hotkey, toggle and push-to-talk state handling, an in-memory
history model, and a non-activating animated floating overlay. It intentionally
contains no microphone capture or speech recognition implementation.

## Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Swift 6 toolchain

## Build and run

```sh
swift build
swift run
```

To build an ad-hoc signed application bundle using Apple Command Line Tools:

```sh
./scripts/build-app.sh
open dist/VoiceInput.app
```

After launch, use the waveform icon in the macOS menu bar. The app does not open
a regular window automatically.

## Structure

- `App` — application lifecycle, menu bar, and window coordination
- `Settings` — persisted hotkey, recording mode, and language preferences
- `History` — history model, store, and empty-state window
- `Hotkey` — recorder control, shortcut model, and global `CGEventTap`
- `Dictation` — testable state machine and temporary simulated processing
- `Overlay` — non-activating AppKit panel and animated state indicator
- `Permissions` — Input Monitoring permission status and request handling

The default shortcut is Right Command. Input Monitoring and Accessibility can
be requested from Settings. For a stable TCC identity, run the app from
`dist/VoiceInput.app`; its bundle identifier is always `com.local.voiceinput`.
The permission status refreshes automatically after returning from System
Settings, and the global event tap starts as soon as both permissions are ready.

See `THIRD_PARTY_NOTICES.md` for the MIT attribution covering the portions
adapted from SuperDictate/Parakey.
