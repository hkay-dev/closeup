#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${SCRCPY_SERVER_PATH:-}" ]]; then
    server=$SCRCPY_SERVER_PATH
else
    scripts/build-server.sh
    server=build/scrcpy-server-webcam.jar
fi

# Flags (--jobs, build system) come from the shared Mac env. `scripts/dev.sh build` sets CLOSEUP_CONFIG=debug and writes
# build/debug/Closeup.app; ship and release.sh build release into build/Closeup.app. UNIVERSAL=1 builds for Apple silicon and Intel Macs in one binary (release.sh does);
# otherwise this Mac's chip.
. mac-env.sh || exit 1
mac_swift_build_flags
config="${CLOSEUP_CONFIG:-release}"
arch_flags=()
if [[ "${UNIVERSAL:-}" == 1 ]]; then arch_flags=(--arch arm64 --arch x86_64); fi
swift build -c "$config" "${MAC_SWIFT_BUILD_FLAGS[@]}" ${arch_flags[@]+"${arch_flags[@]}"}
binary_dir=$(swift build -c "$config" "${MAC_SWIFT_BUILD_FLAGS[@]}" ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)
# Debug (check, dev) and release (ship, release.sh) bundles live apart, so a check running during a ship can't hand the
# ship a debug bundle (android-webcam#ankw).
app='build/Closeup.app'
if [[ "$config" == debug ]]; then app='build/debug/Closeup.app'; fi
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Closeup" "$app/Contents/MacOS/Closeup"
cp Resources/Info.plist "$app/Contents/Info.plist"
# release.sh sets these from the version and commit count, so Settings and Copy Diagnostics tell releases apart.
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
cp Resources/obs-camera.mp4 "$app/Contents/Resources/obs-camera.mp4"
# Every Mac app signs with the one shared identity, dev builds too, so macOS keeps one code identity per app.
codesign --force --sign "Vesper Self-Signed" "$app"
printf '%s\n' "$PWD/$app"
