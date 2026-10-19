#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

server="${SCRCPY_SERVER_PATH:-/opt/homebrew/Cellar/scrcpy/5.0/share/scrcpy/scrcpy-server}"
expected=26cbc9ad0aced6c2282455bef4fb43462605c1f8758c74b4ab1dbf818c229daa
actual=$(shasum -a 256 "$server" | awk '{print $1}')
if [[ "$actual" != "$expected" ]]; then
    echo 'The scrcpy-server 5.0 checksum does not match.' >&2
    exit 1
fi

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app='build/Android Webcam.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/AndroidWebcam" "$app/Contents/MacOS/AndroidWebcam"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$server" "$app/Contents/Resources/scrcpy-server-5.0.jar"
cp Resources/scrcpy-LICENSE.txt "$app/Contents/Resources/scrcpy-LICENSE.txt"
codesign --force --sign - "$app"
printf '%s\n' "$PWD/$app"
