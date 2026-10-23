#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${SCRCPY_SERVER_PATH:-}" ]]; then
    server=$SCRCPY_SERVER_PATH
else
    scripts/build-server.sh
    server=build/scrcpy-server-webcam.jar
fi

# UNIVERSAL=1 builds for Apple silicon and Intel Macs in one binary (CI's releases do); otherwise this Mac's chip.
arch_flags=()
if [[ "${UNIVERSAL:-}" == 1 ]]; then arch_flags=(--arch arm64 --arch x86_64); fi
swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
binary_dir=$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)
app='build/Closeup.app'
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Closeup" "$app/Contents/MacOS/Closeup"
cp Resources/Info.plist "$app/Contents/Info.plist"
# CI sets these from the tag and run number, so Settings and Copy Diagnostics tell releases apart.
if [[ -n "${APP_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "${APP_VERSION#v}" "$app/Contents/Info.plist"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
    plutil -replace CFBundleVersion -string "$APP_BUILD" "$app/Contents/Info.plist"
fi
cp "$server" "$app/Contents/Resources/scrcpy-server.jar"
cp Resources/scrcpy-LICENSE.txt "$app/Contents/Resources/scrcpy-LICENSE.txt"
cp LICENSE NOTICE "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
printf '%s\n' "$PWD/$app"
