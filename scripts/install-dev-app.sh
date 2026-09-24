#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/VoiceInput.app"
INSTALL_ROOT="$HOME/Applications"
TARGET_APP="$INSTALL_ROOT/VoiceInput.app"

if [[ -z "${VOICEINPUT_SIGNING_IDENTITY:-}" ]]; then
    if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/grep -Fq '"VoiceInput Local Development"'; then
        export VOICEINPUT_SIGNING_IDENTITY="VoiceInput Local Development"
    else
        DETECTED_IDENTITY="$(
            /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
                | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(Apple Development:.*|Developer ID Application:.*)"$/\1/p' \
                | /usr/bin/head -n 1
        )"
        if [[ -n "$DETECTED_IDENTITY" ]]; then
            export VOICEINPUT_SIGNING_IDENTITY="$DETECTED_IDENTITY"
        else
            printf 'VoiceInput: no persistent code-signing identity is available.\n' >&2
            printf 'Create "VoiceInput Local Development" using the README instructions first.\n' >&2
            exit 1
        fi
    fi
fi

"$ROOT_DIR/scripts/build-app.sh"

SIGNING_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$SOURCE_APP" 2>&1)"
if /usr/bin/grep -Fq 'Signature=adhoc' <<<"$SIGNING_DETAILS"; then
    printf 'VoiceInput: refusing to install an ad-hoc build at the stable development path.\n' >&2
    printf 'Create a persistent certificate or set VOICEINPUT_SIGNING_IDENTITY first.\n' >&2
    exit 1
fi

/bin/mkdir -p "$INSTALL_ROOT"
STAGE_DIR="$(mktemp -d "$INSTALL_ROOT/.voiceinput-install.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGE_DIR/VoiceInput.app"
/usr/bin/codesign --verify --deep --strict "$STAGE_DIR/VoiceInput.app"

if [[ -e "$TARGET_APP" ]]; then
    [[ "$TARGET_APP" == "$HOME/Applications/VoiceInput.app" ]] || exit 1
    /bin/rm -rf "$TARGET_APP"
fi
/bin/mv "$STAGE_DIR/VoiceInput.app" "$TARGET_APP"
trap - EXIT
/bin/rm -rf "$STAGE_DIR"

printf 'VoiceInput: installed persistent development build at %s\n' "$TARGET_APP"
printf 'Run: open %q\n' "$TARGET_APP"
/usr/bin/codesign -dv --verbose=4 "$TARGET_APP" 2>&1
printf '\nDesignated requirement:\n'
/usr/bin/codesign -dr - "$TARGET_APP" 2>&1
