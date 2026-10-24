#!/usr/bin/env bash
# `tend ship closeup` runs this: builds the committed HEAD with scripts/build-app.sh, quits the running
# Closeup, replaces the installed app, relaunches it and writes the installed commit to
# build/installed-commit. It never pushes; `tend ship` does that.
#
# build-app.sh signs ad hoc, so macOS treats every install as a new app and asks again for the camera,
# microphone and local network access. Fixing that needs a stable signing identity, which this project
# doesn't have yet.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

destination="/Applications/Closeup.app"
[[ -w /Applications ]] || destination="$HOME/Applications/Closeup.app"
destination="${CLOSEUP_INSTALL_DESTINATION:-$destination}"
record="$root/build/installed-commit"

dirty="$(git status --porcelain --untracked-files=no)"
if [[ -n "$dirty" ]]; then
    echo "Commit these changes first; only committed code ships:" >&2
    printf '%s\n' "$dirty" >&2
    exit 1
fi
commit="$(git rev-parse HEAD)"

# Only the installed copy: dev instances (scripts/dev.sh) run the same binary name from build/.
running() { pgrep -qf "^${destination}/Contents/MacOS/Closeup"; }

scripts/build-app.sh
built="$root/build/Closeup.app"
codesign --verify --strict "$built"

if running; then
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

mkdir -p "$(dirname "$destination")"
rm -rf "${destination:?}"
cp -R "$built" "$destination"
open "$destination"
for _ in $(seq 1 50); do
    running && break
    sleep 0.2
done
if ! running; then
    echo "Closeup is not running after the install." >&2
    exit 1
fi

printf '%s\n' "$commit" >"$record"
echo "Installed Closeup ${commit:0:9} at $destination"
