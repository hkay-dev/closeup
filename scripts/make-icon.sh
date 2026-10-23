#!/usr/bin/env bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
# Run from the repository root: ./scripts/make-icon.sh
# Needs rsvg-convert (brew install librsvg) and iconutil (ships with macOS).
set -euo pipefail

src="Resources/AppIcon.svg"
out="Resources/AppIcon.icns"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
iconset="$tmp/AppIcon.iconset"
mkdir "$iconset"

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$src" -o "$iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    rsvg-convert -w "$double" -h "$double" "$src" -o "$iconset/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$iconset" -o "$out"
echo "Wrote $out"
