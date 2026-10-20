#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${SCRCPY_SERVER_PATH:-}" ]]; then
    server=$SCRCPY_SERVER_PATH
else
    scripts/build-server.sh
    server=build/scrcpy-server-webcam.jar
fi

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app='build/Android Webcam.app'
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/AndroidWebcam" "$app/Contents/MacOS/AndroidWebcam"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$server" "$app/Contents/Resources/scrcpy-server.jar"
cp Resources/scrcpy-LICENSE.txt "$app/Contents/Resources/scrcpy-LICENSE.txt"
codesign --force --sign - "$app"
printf '%s\n' "$PWD/$app"
