#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

server_url=https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-server-v5.0.1
expected=764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536
cache=build/cache/scrcpy-server-v5.0.1

if [[ -n "${SCRCPY_SERVER_PATH:-}" ]]; then
    server=$SCRCPY_SERVER_PATH
else
    server=$cache
    if [[ ! -f "$server" ]]; then
        mkdir -p build/cache
        echo "Downloading scrcpy-server 5.0.1."
        curl -fsSL "$server_url" -o "$server.tmp"
        mv "$server.tmp" "$server"
    fi
fi

actual=$(shasum -a 256 "$server" | awk '{print $1}')
if [[ "$actual" != "$expected" ]]; then
    echo "The scrcpy-server 5.0.1 checksum does not match: $server" >&2
    if [[ "$server" == "$cache" ]]; then
        rm -f "$server"
        echo 'Deleted the cached copy. Run the script again to download it.' >&2
    fi
    exit 1
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
