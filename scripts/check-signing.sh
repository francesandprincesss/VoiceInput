#!/bin/bash

set -euo pipefail

printf 'Available code-signing identities:\n'
/usr/bin/security find-identity -v -p codesigning

printf '\nPreferred VoiceInput identity:\n'
if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -Fq '"VoiceInput Local Development"'; then
    printf 'VoiceInput Local Development\n'
else
    printf 'Not found. See README.md -> Stable development signing.\n'
fi
