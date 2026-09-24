#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_APP="$ROOT_DIR/dist/VoiceInput.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
EXPECTED_BUNDLE_IDENTIFIER="com.local.voiceinput"

fail() {
    printf 'VoiceInput: %s\n' "$*" >&2
    exit 1
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "macOS is required."
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "Apple Silicon is required."
command -v swift >/dev/null 2>&1 || fail "Swift is missing. Install Apple Command Line Tools."
command -v codesign >/dev/null 2>&1 || fail "codesign is missing. Install Apple Command Line Tools."

BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
[[ "$BUNDLE_IDENTIFIER" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] \
    || fail "Unexpected CFBundleIdentifier: $BUNDLE_IDENTIFIER"
printf 'VoiceInput: bundle identifier %s\n' "$BUNDLE_IDENTIFIER"

printf 'VoiceInput: building arm64 release binary...\n'
swift build -c release --arch arm64 --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --arch arm64 --package-path "$ROOT_DIR" --show-bin-path)"
BIN="$BIN_DIR/VoiceInput"
[[ -x "$BIN" ]] || fail "SwiftPM did not produce $BIN"
/usr/bin/file "$BIN" | /usr/bin/grep -q 'arm64' || fail "The executable is not arm64."

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceinput-build.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE_APP="$STAGE_DIR/VoiceInput.app"
/bin/mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
/bin/cp "$BIN" "$STAGE_APP/Contents/MacOS/VoiceInput"
/bin/cp "$INFO_PLIST" "$STAGE_APP/Contents/Info.plist"
/bin/cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGE_APP/Contents/Resources/"
/bin/chmod 755 "$STAGE_APP/Contents/MacOS/VoiceInput"

printf 'VoiceInput: signing with identity %s...\n' "$SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --deep --sign - --options runtime --timestamp=none "$STAGE_APP"
else
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$STAGE_APP"
fi
/usr/bin/codesign --verify --deep --strict "$STAGE_APP"

/bin/mkdir -p "$ROOT_DIR/dist"
if [[ -e "$OUTPUT_APP" ]]; then
    [[ "$OUTPUT_APP" == "$ROOT_DIR/dist/VoiceInput.app" ]] || fail "Unexpected output path."
    /bin/rm -rf "$OUTPUT_APP"
fi
/bin/mv "$STAGE_APP" "$OUTPUT_APP"
trap - EXIT
/bin/rm -rf "$STAGE_DIR"

printf 'VoiceInput: built %s\n' "$OUTPUT_APP"
