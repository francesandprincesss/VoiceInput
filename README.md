# VoiceInput

Minimal native menu bar application for macOS on Apple Silicon. It includes a
recordable global hotkey, toggle and push-to-talk handling, local microphone
capture, FluidAudio/Parakeet TDT v3 transcription, persisted history, Unicode
text insertion, and a non-activating animated floating overlay. Recognition is
local after FluidAudio's one-time model download.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer (required by FluidAudio 0.15.5)
- Swift 6 toolchain

## Build and run

```sh
swift build
swift run
```

To build an application bundle using Apple Command Line Tools:

```sh
./scripts/build-app.sh
open dist/VoiceInput.app
```

The build script prefers a persistent code-signing identity. If none is
available it falls back to ad-hoc signing and prints a prominent warning.

After launch, use the waveform icon in the macOS menu bar. The app does not open
a regular window automatically.

## Structure

- `App` — application lifecycle, menu bar, and window coordination
- `Settings` — persisted hotkey, recording, language, and Local/API preferences
- `Audio` — AVAudioEngine capture and real RMS level monitoring
- `History` — persisted history model and window
- `Hotkey` — recorder control, shortcut model, and global `CGEventTap`
- `Dictation` — testable recording/transcription/insertion pipeline
- `Input` — Accessibility target capture and Unicode text insertion
- `Overlay` — non-activating AppKit panel and animated state indicator
- `Permissions` — Input Monitoring, Accessibility, and Microphone permissions
- `Speech` — recognizer router, FluidAudio model lifecycle, and secure credential abstraction

The default shortcut is Right Command. Input Monitoring and Accessibility can
be requested from Settings. The bundle identifier is always
`com.local.voiceinput`. Permission status refreshes after returning from System
Settings, and the global event tap starts as soon as both permissions are ready.

## Stable development signing

macOS privacy permissions are associated with the application's code-signing
requirement as well as its bundle identifier and location. An ad-hoc signature
has a requirement based on a binary hash, so that identity can change after a
rebuild. Create one persistent local certificate and reuse it for every build.

Using Keychain Access, without Xcode:

1. Open **Keychain Access** and select the **login** keychain.
2. Choose **Keychain Access → Certificate Assistant → Create a Certificate**.
3. Set **Name** to `VoiceInput Local Development`.
4. Set **Identity Type** to **Self Signed Root**.
5. Set **Certificate Type** to **Code Signing**.
6. Create the certificate in the login keychain. If Certificate Assistant asks
   for a key pair, let Keychain Access create and retain its private key.
7. Open the new certificate in Keychain Access. Under **Trust**, set **Code
   Signing** to **Always Trust** if macOS does not initially consider the
   identity valid, then close the window and authenticate the change.
8. Verify it once:

```sh
./scripts/check-signing.sh
security find-identity -v -p codesigning
```

The output should contain `VoiceInput Local Development`. Do not recreate this
certificate for normal rebuilds. The scripts never generate or export private
keys and never call `tccutil reset`.

You can select that identity explicitly:

```sh
export VOICEINPUT_SIGNING_IDENTITY="VoiceInput Local Development"
./scripts/build-app.sh
```

`build-app.sh` automatically selects the same named identity when it is valid.
It also recognizes an existing Apple Development or Developer ID Application
identity. If no persistent identity exists, an ad-hoc `dist` build is still
produced, but it is not suitable for stable TCC permissions.

For normal development, always install and launch from the fixed location:

```sh
./scripts/install-dev-app.sh
open /Applications/VoiceInput.app
```

`install-dev-app.sh` refuses to replace the fixed application with an ad-hoc
build. It stops an existing VoiceInput process, installs the new bundle,
launches the copy at the fixed development path, and verifies the executable
path of the running process. Keep all three values stable between builds:

- bundle identifier: `com.local.voiceinput`;
- signing certificate: `VoiceInput Local Development`;
- application path: `/Applications/VoiceInput.app`.

`install-dev-app.sh` uses `sudo` only when the current user cannot write to
`/Applications`. If the previous `~/Applications/VoiceInput.app` path still
exists, the script reports it as a duplicate but does not delete it.

Both build scripts verify the final signature. `build-app.sh` prints the full
`codesign -dv --verbose=4` output and the designated requirement.

## Application icon

The source artwork is `Resources/AppIcon/app-icon-source.svg`. Every app-bundle
build runs `scripts/generate-app-icon.sh`, which uses the macOS system tools
`qlmanage`, `sips`, and `iconutil` to produce the standard 16–1024 px iconset
and `Resources/AppIcon/VoiceInput.icns`. Generated files are reused while they
are newer than the SVG and generator script. The ICNS file is copied to the
app bundle and selected by `CFBundleIconFile` in `Resources/Info.plist`.

Finder and Launchpad cache application icons. After installing, verify the
icon on `/Applications/VoiceInput.app` (or in **Get Info**) and allow Finder or
Launchpad a little time to refresh if an older icon is still shown. No system
cache reset is required.

## Speech recognition mode

Settings contains **Use API Transcription**, which is off by default:

- Off uses the existing local Parakeet TDT 0.6B v3 pipeline.
- On selects the API route, which currently reports `API provider is not
  configured.` and sends no audio anywhere.

Future provider credentials must use `SecureCredentialStore`, whose production
implementation stores data in the macOS Keychain. Secrets are not stored in
UserDefaults, plist files, JSON, or source code.

See `THIRD_PARTY_NOTICES.md` for the MIT attribution covering the portions
adapted from SuperDictate/Parakey.
