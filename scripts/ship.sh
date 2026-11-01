#!/usr/bin/env bash
# `deckhand ship run android-webcam` runs this: builds the committed HEAD with scripts/build-app.sh (under the qm build
# gate), replaces the installed Closeup and reopens it in the background if it was running. The install is the shared
# ship_install from armada-ship-lib.sh: with ARMADA_SHIP_STAGED=1 the running copy keeps running (moved aside to
# .Closeup-old.* until it quits, since macOS loses a running app's code identity, and its camera and other privacy
# grants, when its files go, android-webcam#6fx8) and the new build opens at the next Restart, which quits and reopens
# the app. Deckhand records the installed commit; it never pushes either, `deckhand ship run` does that.
#
# build-app.sh and this script sign with "Vesper Self-Signed" (the one self-signed certificate every Mac app
# uses, in the login keychain), so camera, microphone and local network grants carry across ships. A certificate
# change is a new identity and resets the grants once.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

destination="/Applications/Closeup.app"
[[ -w /Applications ]] || destination="$HOME/Applications/Closeup.app"
destination="${CLOSEUP_INSTALL_DESTINATION:-$destination}"
identity="Vesper Self-Signed"

dirty="$(git status --porcelain --untracked-files=no)"
if [[ -n "$dirty" ]]; then
    echo "Commit these changes first; only committed code ships:" >&2
    printf '%s\n' "$dirty" >&2
    exit 1
fi
commit="$(git rev-parse HEAD)"

if ! security find-identity -v -p codesigning | grep -q "\"$identity\""; then
    echo "The signing identity \"$identity\" is missing from the login keychain; docs/working-here.md names the shared certificate." >&2
    exit 1
fi

if command -v qm >/dev/null 2>&1; then qm with build android-webcam -- scripts/build-app.sh; else scripts/build-app.sh; fi
stage="$(mktemp -d "$root/build/ship-stage.XXXXXX")"
trap 'rm -rf "${stage:?}"' EXIT
built="$stage/Closeup.app"
cp -R build/Closeup.app "$built"
codesign --force --timestamp=none -s "$identity" "$built"
codesign --verify --strict "$built"

requirement() { codesign -d -r- "$1" 2>&1 | grep '^designated =>' | sed 's/^designated => //'; }
if [[ -d "$destination" ]] && codesign -dv "$destination" 2>&1 | grep -q "Authority=$identity"; then
    if [[ "$(requirement "$built")" != "$(requirement "$destination")" ]]; then
        echo "The new build's designated requirement differs from the installed app's, so macOS would reset its permissions." >&2
        exit 1
    fi
fi

name=Closeup
dest_dir="$(dirname "$destination")"
app="$built" # a copy made above, so the move by ship_install leaves build/ alone
# shellcheck source=/dev/null
. "$(command -v armada-ship-lib.sh)"
ship_install

echo "Installed Closeup ${commit:0:9} at $destination"
