#!/usr/bin/env bash
# `deckhand ship run android-webcam` runs this: builds the committed HEAD with scripts/build-app.sh (release, under the
# qm build gate), replaces the installed Closeup and reopens it in the background if it was running. The steps live in
# armada-ship-lib.sh on PATH. The install is ship_install: with ARMADA_SHIP_STAGED=1 the running copy keeps running
# (moved aside to .Closeup-old.* until it quits, since macOS loses a running app's code identity, and its camera and
# other privacy grants, when its files go, android-webcam#6fx8) and the new build opens at the next Restart, which
# quits and reopens the app. Deckhand records the installed commit; it never pushes either, `deckhand ship run` does that.
#
# build-app.sh and this script sign with "Vesper Self-Signed" (the one self-signed certificate every Mac app
# uses, in the login keychain), so camera, microphone and local network grants carry across ships. A certificate
# change is a new identity and resets the grants once.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root=$PWD
lib="$(command -v armada-ship-lib.sh)" || { echo "ship: armada-ship-lib.sh is not on PATH (Armada's bin/ links it into ~/.local/bin)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$lib"

name="Closeup"
project="android-webcam"
identity="Vesper Self-Signed"
dest_dir="/Applications"
[[ -w /Applications ]] || dest_dir="$HOME/Applications"
destination="${CLOSEUP_INSTALL_DESTINATION:-$dest_dir/$name.app}"
dest_dir="$(dirname "$destination")"
record="$root/build/stable-installed-commit"

ship_check_clean
ship_check_identity
ship_lock
ship_stage

echo "::step Build the app"
ship_build env CLOSEUP_CONFIG=release scripts/build-app.sh
ditto build/Closeup.app "$app" # build-app.sh already signed the release bundle with Vesper Self-Signed
codesign --verify --deep --strict "$app"
ship_check_requirement
ship_install
ship_record
echo "ship: installed $name ${commit:0:9} at $destination"
