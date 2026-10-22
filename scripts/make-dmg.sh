#!/usr/bin/env bash
# Packs the built app into a compressed, read-only disk image with an Applications link,
# so a user drags the app across. No Finder styling: that needs a GUI session and breaks in CI.
# Usage: scripts/make-dmg.sh [APP] [OUT]   (defaults: build/Android Webcam.app, build/Android-Webcam.dmg)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-$root/build/Android Webcam.app}
out=${2:-$root/build/Android-Webcam.dmg}
volume='Android Webcam'

fail() { printf 'make-dmg: %s\n' "$*" >&2; exit 1; }

[[ -d "$app" ]] || fail "no app at $app (run scripts/build-app.sh first)"
[[ -x "$app/Contents/MacOS/AndroidWebcam" ]] || fail "$app has no Contents/MacOS/AndroidWebcam"
codesign --verify --strict "$app" || fail "$app isn't signed (scripts/build-app.sh signs it)"
mkdir -p "$(dirname "$out")" || fail "can't make the folder for $out"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

staging=$(mktemp -d "${TMPDIR:-/tmp}/android-webcam-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT

# ditto keeps the bundle's permissions, extended attributes and signature.
ditto "$app" "$staging/$(basename "$app")"
ln -s /Applications "$staging/Applications"

rm -f "$out"
# Show hdiutil's output only when it fails: newer macOS also prints a deprecation note for
# `create` on every run, which says nothing about this image.
if ! log=$(hdiutil create -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$out" 2>&1); then
    printf '%s\n' "$log" >&2
    fail "hdiutil create failed for $out"
fi
hdiutil verify "$out" >/dev/null 2>&1 || fail "hdiutil verify failed for $out"
printf '%s\n' "$out"
