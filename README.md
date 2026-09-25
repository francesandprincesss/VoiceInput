# VoiceInput

Fast, private voice-to-text for macOS.

Local speech recognition, global hotkeys, and instant text insertion.

<!-- Overlay demo placeholder. Add docs/images/overlay-demo.gif, then remove
the opening and closing comment markers around the block below.

<p align="center">
  <img src="docs/images/overlay-demo.gif"
       alt="VoiceInput dictation overlay"
       width="720">
</p>

-->

## About

VoiceInput is a lightweight macOS dictation app. Press or hold a global
hotkey, speak, and the transcription appears directly in the field you were
using.

The interface stays out of the way: a menu bar app, a compact floating overlay,
and a local-first speech pipeline designed for quick everyday input.

## Features

- Local speech recognition with Parakeet TDT 0.6B v3
- Russian and English transcription
- Push-to-Talk and Toggle recording modes
- Custom global hotkeys
- Text insertion into the active field
- Locally stored dictation history
- Monochrome floating recording overlay
- Native Apple Silicon application

## How it works

**Press → Speak → Release → Text appears**

Toggle mode uses a second press instead of a release. The overlay follows the
recording, processing, and insertion states without taking keyboard focus.

## Privacy

Local transcription is the default working mode. After the initial model
download, recognition runs on your Mac and requires no cloud account.
Dictation history is stored locally.

The API transcription setting is currently an unconfigured placeholder; no API
provider is included.

## Getting started

```sh
git clone https://github.com/francesandprincesss/VoiceInput.git
cd VoiceInput
swift build
./scripts/install-dev-app.sh
```

The development app is installed and launched from:

```text
/Applications/VoiceInput.app
```

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift toolchain and Apple Command Line Tools

## Permissions

VoiceInput requires **Microphone** access to record speech, **Input Monitoring**
for the global hotkey, and **Accessibility** to insert text into the active
application.

## Tech stack

- Swift
- SwiftUI and AppKit
- AVAudioEngine
- Core ML and FluidAudio
- NVIDIA Parakeet
- macOS Accessibility APIs

## Acknowledgements

VoiceInput uses [FluidAudio](https://github.com/FluidInference/FluidAudio) and
[NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
for local speech recognition. Portions of the hotkey and floating overlay work
were adapted from [SuperDictate](https://github.com/shlgd/SuperDictate).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[MODEL_ATTRIBUTION.md](MODEL_ATTRIBUTION.md) for licenses and attribution.
