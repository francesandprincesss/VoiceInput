#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SVG="$ROOT_DIR/Resources/AppIcon/app-icon-source.svg"
OUTPUT_DIR="$ROOT_DIR/Resources/AppIcon"
ICONSET_DIR="$OUTPUT_DIR/VoiceInput.iconset"
OUTPUT_ICNS="$OUTPUT_DIR/VoiceInput.icns"

fail() {
    printf 'VoiceInput icon: %s\n' "$*" >&2
    exit 1
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "macOS is required."
[[ -f "$SOURCE_SVG" ]] || fail "source SVG is missing: $SOURCE_SVG"
command -v qlmanage >/dev/null 2>&1 || fail "qlmanage is missing."
command -v sips >/dev/null 2>&1 || fail "sips is missing."
command -v iconutil >/dev/null 2>&1 || fail "iconutil is missing."

EXPECTED_FILES=(
    icon_16x16.png
    icon_16x16@2x.png
    icon_32x32.png
    icon_32x32@2x.png
    icon_128x128.png
    icon_128x128@2x.png
    icon_256x256.png
    icon_256x256@2x.png
    icon_512x512.png
    icon_512x512@2x.png
)

is_current=true
[[ -f "$OUTPUT_ICNS" && "$OUTPUT_ICNS" -nt "$SOURCE_SVG" && "$OUTPUT_ICNS" -nt "$0" ]] \
    || is_current=false
for filename in "${EXPECTED_FILES[@]}"; do
    [[ -f "$ICONSET_DIR/$filename" && "$ICONSET_DIR/$filename" -nt "$SOURCE_SVG" ]] \
        || is_current=false
done

if [[ "$is_current" == true ]]; then
    printf 'VoiceInput icon: generated assets are current.\n'
    exit 0
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceinput-icon.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
MASTER_PNG="$TEMP_DIR/app-icon-source.svg.png"
TEMP_ICONSET="$TEMP_DIR/VoiceInput.iconset"
/bin/mkdir -p "$TEMP_ICONSET" "$OUTPUT_DIR"

printf 'VoiceInput icon: rendering %s at 1024x1024...\n' "$SOURCE_SVG"
/usr/bin/qlmanage -t -s 1024 -o "$TEMP_DIR" "$SOURCE_SVG" >/dev/null
[[ -f "$MASTER_PNG" ]] || fail "qlmanage did not produce the expected PNG."

MASTER_WIDTH="$(/usr/bin/sips -g pixelWidth "$MASTER_PNG" | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
MASTER_HEIGHT="$(/usr/bin/sips -g pixelHeight "$MASTER_PNG" | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
[[ "$MASTER_WIDTH" == "1024" && "$MASTER_HEIGHT" == "1024" ]] \
    || fail "rendered source must be 1024x1024, got ${MASTER_WIDTH}x${MASTER_HEIGHT}."

render_size() {
    local pixels="$1"
    local filename="$2"
    /usr/bin/sips -z "$pixels" "$pixels" "$MASTER_PNG" \
        --out "$TEMP_ICONSET/$filename" >/dev/null
}

render_size 16 icon_16x16.png
render_size 32 icon_16x16@2x.png
render_size 32 icon_32x32.png
render_size 64 icon_32x32@2x.png
render_size 128 icon_128x128.png
render_size 256 icon_128x128@2x.png
render_size 256 icon_256x256.png
render_size 512 icon_256x256@2x.png
render_size 512 icon_512x512.png
render_size 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$TEMP_ICONSET" -o "$TEMP_DIR/VoiceInput.icns"
[[ -s "$TEMP_DIR/VoiceInput.icns" ]] || fail "iconutil did not produce VoiceInput.icns."

/bin/mkdir -p "$ICONSET_DIR"
for filename in "${EXPECTED_FILES[@]}"; do
    /bin/cp "$TEMP_ICONSET/$filename" "$ICONSET_DIR/$filename"
done
/bin/cp "$TEMP_DIR/VoiceInput.icns" "$OUTPUT_ICNS"

printf 'VoiceInput icon: generated %s\n' "$OUTPUT_ICNS"
