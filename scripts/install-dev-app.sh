#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/VoiceInput.app"
INSTALL_ROOT="/Applications"
TARGET_APP="$INSTALL_ROOT/VoiceInput.app"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/VoiceInput"
LEGACY_APP="$HOME/Applications/VoiceInput.app"
PROCESS_NAME="VoiceInput"

fail() {
    printf 'VoiceInput: %s\n' "$*" >&2
    exit 1
}

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

if /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    printf 'VoiceInput: stopping the running instance before installation...\n'
    /usr/bin/pkill -x "$PROCESS_NAME" || true
    for _ in {1..50}; do
        /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1 || break
        /bin/sleep 0.1
    done
    /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1 \
        && fail "the previous VoiceInput process did not stop."
fi

if [[ -d "$LEGACY_APP" ]]; then
    printf '\n' >&2
    printf 'VoiceInput: warning: duplicate installation exists at %s.\n' "$LEGACY_APP" >&2
    printf 'VoiceInput: /Applications/VoiceInput.app is the canonical development installation.\n' >&2
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceinput-install.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGE_DIR/VoiceInput.app"
/usr/bin/codesign --verify --deep --strict "$STAGE_DIR/VoiceInput.app"

[[ "$TARGET_APP" == "/Applications/VoiceInput.app" ]] \
    || fail "unexpected installation target: $TARGET_APP"

if [[ -d "$TARGET_APP" && -w "$TARGET_APP" ]]; then
    # A user-owned development bundle can be updated in place even when the
    # /Applications directory itself requires administrator authorization.
    /bin/rm -rf "$TARGET_APP/Contents"
    /usr/bin/ditto "$STAGE_DIR/VoiceInput.app" "$TARGET_APP"
elif [[ -w "$INSTALL_ROOT" ]]; then
    if [[ -e "$TARGET_APP" ]]; then
        /bin/rm -rf "$TARGET_APP"
    fi
    /usr/bin/ditto "$STAGE_DIR/VoiceInput.app" "$TARGET_APP"
else
    command -v sudo >/dev/null 2>&1 || fail "sudo is required to write to /Applications."
    printf 'VoiceInput: administrator authorization is required to update %s\n' "$TARGET_APP"
    if [[ -e "$TARGET_APP" ]]; then
        /usr/bin/sudo /bin/rm -rf "$TARGET_APP"
    fi
    /usr/bin/sudo /usr/bin/ditto "$STAGE_DIR/VoiceInput.app" "$TARGET_APP"
fi
trap - EXIT
/bin/rm -rf "$STAGE_DIR"

printf 'VoiceInput: installed persistent development build at %s\n' "$TARGET_APP"
/usr/bin/codesign -dv --verbose=4 "$TARGET_APP" 2>&1
printf '\nDesignated requirement:\n'
/usr/bin/codesign -dr - "$TARGET_APP" 2>&1

printf '\nVoiceInput: launching %s\n' "$TARGET_APP"
/usr/bin/open -n "$TARGET_APP"

RUNNING_PID=""
for _ in {1..50}; do
    RUNNING_PID="$(/usr/bin/pgrep -x "$PROCESS_NAME" | /usr/bin/head -n 1 || true)"
    [[ -n "$RUNNING_PID" ]] && break
    /bin/sleep 0.1
done
[[ -n "$RUNNING_PID" ]] || fail "the installed application did not remain running."

RUNNING_EXECUTABLE="$(
    /usr/sbin/lsof -a -p "$RUNNING_PID" -d txt -Fn 2>/dev/null \
        | /usr/bin/sed -n 's/^n//p' \
        | /usr/bin/grep '/Contents/MacOS/VoiceInput$' \
        | /usr/bin/head -n 1 \
        || true
)"
[[ "$RUNNING_EXECUTABLE" == "$TARGET_EXECUTABLE" ]] \
    || fail "unexpected running executable: ${RUNNING_EXECUTABLE:-unknown}"

printf 'VoiceInput: running PID %s from %s\n' "$RUNNING_PID" "$RUNNING_EXECUTABLE"
