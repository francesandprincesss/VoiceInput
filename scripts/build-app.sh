#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_APP="$ROOT_DIR/dist/VoiceInput.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/VoiceInput.entitlements"
EXPECTED_BUNDLE_IDENTIFIER="com.local.voiceinput"

fail() {
    printf 'VoiceInput: %s\n' "$*" >&2
    exit 1
}

available_identities() {
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/p'
}

identity_exists() {
    local requested="$1"
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/grep -Fq "\"$requested\""
}

select_signing_identity() {
    local requested="${VOICEINPUT_SIGNING_IDENTITY:-}"
    if [[ -n "$requested" ]]; then
        identity_exists "$requested" \
            || fail "VOICEINPUT_SIGNING_IDENTITY is not a valid code-signing identity: $requested"
        printf '%s\n' "$requested"
        return
    fi

    if identity_exists "VoiceInput Local Development"; then
        printf '%s\n' "VoiceInput Local Development"
        return
    fi

    local candidate
    while IFS= read -r candidate; do
        case "$candidate" in
            "Apple Development:"*|"Developer ID Application:"*)
                printf '%s\n' "$candidate"
                return
                ;;
        esac
    done < <(available_identities)

    printf '%s\n' "-"
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "macOS is required."
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "Apple Silicon is required."
command -v swift >/dev/null 2>&1 || fail "Swift is missing. Install Apple Command Line Tools."
command -v codesign >/dev/null 2>&1 || fail "codesign is missing. Install Apple Command Line Tools."
command -v security >/dev/null 2>&1 || fail "security is missing. Install Apple Command Line Tools."

SIGN_IDENTITY="$(select_signing_identity)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    printf '\n' >&2
    printf '======================================================================\n' >&2
    printf 'WARNING: Using ad-hoc signing. macOS may reset Privacy permissions after rebuilds.\n' >&2
    printf 'Create "VoiceInput Local Development" once, then run scripts/install-dev-app.sh.\n' >&2
    printf '======================================================================\n' >&2
    printf '\n' >&2
else
    printf 'VoiceInput: using persistent signing identity "%s"\n' "$SIGN_IDENTITY"
fi

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
/bin/cp "$ROOT_DIR/MODEL_ATTRIBUTION.md" "$STAGE_APP/Contents/Resources/"
/bin/chmod 755 "$STAGE_APP/Contents/MacOS/VoiceInput"

printf 'VoiceInput: signing with identity %s...\n' "$SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --deep --sign - --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$STAGE_APP"
else
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$STAGE_APP"
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
printf '\nVoiceInput: code-signing details\n'
/usr/bin/codesign -dv --verbose=4 "$OUTPUT_APP" 2>&1
printf '\nVoiceInput: designated requirement\n'
/usr/bin/codesign -dr - "$OUTPUT_APP" 2>&1
