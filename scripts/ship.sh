#!/usr/bin/env bash
# `deckhand ship run android-webcam` runs this: builds the committed HEAD with scripts/build-app.sh (under the qm build
# gate), replaces the installed Closeup and reopens it in the background if it was running. With ARMADA_SHIP_STAGED=1 it
# swaps the app in without quitting or reopening it (Deck's Restart card does that). Deckhand records the installed
# commit; it never pushes either, `deckhand ship run` does that.
#
# build-app.sh signs ad hoc, which macOS treats as a new app on every build. This re-signs the installed
# copy with "Closeup Local Signing" (a self-signed certificate in the login keychain, made once like
# Skylight's), so camera, microphone and local network grants carry across ships. dev.sh builds keep
# the ad-hoc signature. A certificate change is a new identity and resets the grants once.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

destination="/Applications/Closeup.app"
[[ -w /Applications ]] || destination="$HOME/Applications/Closeup.app"
destination="${CLOSEUP_INSTALL_DESTINATION:-$destination}"
identity="Closeup Local Signing"

dirty="$(git status --porcelain --untracked-files=no)"
if [[ -n "$dirty" ]]; then
    echo "Commit these changes first; only committed code ships:" >&2
    printf '%s\n' "$dirty" >&2
    exit 1
fi
commit="$(git rev-parse HEAD)"

# Only the installed copy: dev instances (scripts/dev.sh) run the same binary name from build/.
running() { pgrep -qf "^${destination}/Contents/MacOS/Closeup"; }

if ! security find-identity -v -p codesigning | grep -q "\"$identity\""; then
    echo "The signing identity \"$identity\" is missing from the login keychain; docs/working-here.md says how it was made." >&2
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

was_running=0
if running; then
    was_running=1
    if [[ -z "${ARMADA_SHIP_STAGED:-}" ]]; then
        echo "Quitting Closeup"
        osascript -e "tell application \"$destination\" to quit" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
            running || break
            sleep 0.2
        done
        if running; then
            echo "Closeup did not quit. Quit it and run this again." >&2
            exit 1
        fi
    fi
fi

mkdir -p "$(dirname "$destination")"
rm -rf "${destination:?}"
cp -R "$built" "$destination"

staged=0
if [[ -n "${ARMADA_SHIP_STAGED:-}" ]]; then
    staged=1
elif [[ "$was_running" == 1 ]]; then
    open -g -j "$destination"
    for _ in $(seq 1 50); do
        running && break
        sleep 0.2
    done
    if ! running; then
        echo "Closeup is not running after the install." >&2
        exit 1
    fi
fi

echo "Installed Closeup ${commit:0:9} at $destination"
if [[ "$staged" == 1 ]]; then
    echo "ship: staged, the running copy of Closeup is left as it is"
fi
