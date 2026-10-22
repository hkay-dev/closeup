#!/usr/bin/env bash
# Off-screen dev instance of Android Webcam for agents and scripts (docs/dev-automation.md).
# The instance has its own defaults, no status item, windows parked below the desktop, and a control
# socket that only exists because ANDROID_WEBCAM_DEV_DIR is set. Nothing shows on screen.
#
#   scripts/dev.sh build                 build the app (scripts/build-app.sh) through the build queue
#   scripts/dev.sh start [KEY=VALUE ...] start the instance; prints its directory. KEY=VALUE (KEY:=JSON) seeds its defaults
#   scripts/dev.sh stop                  choose Quit, wait for the process, remove the directory
#   scripts/dev.sh state                 header text, menu items, open windows
#   scripts/dev.sh menu                  header text and menu items only
#   scripts/dev.sh choose TITLE          choose a menu item: "Settings", "Start Webcam", "Image Settings", ...
#   scripts/dev.sh open WINDOW           setup, settings, image, sync or preview
#   scripts/dev.sh close WINDOW
#   scripts/dev.sh windows               open windows with ids, levels and frames
#   scripts/dev.sh text WINDOW           what a window shows, one line each, controls marked
#   scripts/dev.sh tree WINDOW           the accessibility tree as JSON
#   scripts/dev.sh press WINDOW LABEL    press a button or toggle by its label
#   scripts/dev.sh shot WINDOW PATH      save the window as a PNG
#   scripts/dev.sh effects               notifications and outside actions the instance recorded and skipped
#   scripts/dev.sh defaults              the instance's own defaults
#   scripts/dev.sh ctl OP [k=v ...]      any operation (k:=json for a JSON value)
#   scripts/dev.sh smoke [DIR]           the whole journey with checks; screenshots go in DIR
#
# Commands find the instance through $ANDROID_WEBCAM_DEV_DIR, else the one `start` last printed.
# Take the desktop for anything that screenshots: qm with desktop NAME -- scripts/dev.sh smoke
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${ANDROID_WEBCAM_APP:-$root/build/Android Webcam.app/Contents/MacOS/AndroidWebcam}"
# One instance per checkout, so worktrees can each run their own.
pointer="${XDG_CACHE_HOME:-$HOME/.cache}/android-webcam/dev-current-$(printf %s "$root" | shasum | cut -c1-10)"

die() {
    echo "dev.sh: $*" >&2
    exit 2
}

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

current_dir() {
    local dir="${ANDROID_WEBCAM_DEV_DIR:-}"
    [[ -n "$dir" ]] || { [[ -f "$pointer" ]] && dir="$(<"$pointer")"; }
    [[ -n "$dir" && -S "$dir/control.sock" ]] || die "no dev instance running. Run scripts/dev.sh start."
    printf '%s\n' "$dir"
}

ctl() {
    python3 "$root/scripts/dev-ctl.py" "$(current_dir)" "$@"
}

start() {
    [[ -x "$binary" ]] || die "no app at $binary. Run scripts/dev.sh build, or set ANDROID_WEBCAM_APP."
    if [[ -f "$pointer" && -S "$(<"$pointer")/control.sock" ]] && python3 "$root/scripts/dev-ctl.py" "$(<"$pointer")" ping >/dev/null 2>&1; then
        die "a dev instance is already running in $(<"$pointer"). Run scripts/dev.sh stop first."
    fi
    local dir
    dir="$(mktemp -d /tmp/awdev.XXXXXX)"
    # key=value (a string) or key:=json seeds the instance's defaults, such as lensID=1 or setupShown:=true.
    if (( $# )); then
        python3 -c 'import json, sys
seed = {}
for arg in sys.argv[2:]:
    if ":=" in arg: key, value = arg.split(":=", 1); seed[key] = json.loads(value)
    else: key, value = arg.split("=", 1); seed[key] = value
json.dump(seed, open(sys.argv[1] + "/seed.json", "w"))' "$dir" "$@"
    fi
    ANDROID_WEBCAM_DEV_DIR="$dir" nohup "$binary" >"$dir/app.log" 2>&1 &
    echo $! >"$dir/pid"
    disown
    local tries=0
    until python3 "$root/scripts/dev-ctl.py" "$dir" ping >/dev/null 2>&1; do
        kill -0 "$(<"$dir/pid")" 2>/dev/null || { cat "$dir/app.log" >&2; die "the app exited before its control socket came up."; }
        (( ++tries < 100 )) || die "the control socket never answered. Log: $dir/app.log"
        sleep 0.2
    done
    # The first phone list comes from adb a moment after launch; a reply before it would show a stale header.
    tries=0
    until [[ "$(python3 "$root/scripts/dev-ctl.py" "$dir" menu 2>/dev/null | jq -r .ready)" == true ]]; do
        (( ++tries < 75 )) || die "the app never finished its first setup check. Log: $dir/app.log"
        sleep 0.2
    done
    mkdir -p "$(dirname "$pointer")"
    printf '%s\n' "$dir" >"$pointer"
    printf '%s\n' "$dir"
}

stop() {
    local dir pid
    dir="$(current_dir)"
    pid="$(<"$dir/pid")"
    python3 "$root/scripts/dev-ctl.py" "$dir" choose title=Quit >/dev/null 2>&1 || true
    local tries=0
    while kill -0 "$pid" 2>/dev/null; do
        (( ++tries < 100 )) || { kill -TERM "$pid" 2>/dev/null || true; break; }
        sleep 0.1
    done
    rm -rf "$dir" "$pointer"
}

command="${1:-}"
[[ -n "$command" ]] || usage
shift
case "$command" in
    build) exec qm with build "awebcam-$(basename "$root")" -- "$root/scripts/build-app.sh" ;;
    start) start "$@" ;;
    stop) stop ;;
    state | menu | windows | effects | defaults | ping) ctl "$command" ;;
    choose) [[ $# -eq 1 ]] || usage; ctl choose "title=$1" ;;
    open | close | text | tree) [[ $# -eq 1 ]] || usage; ctl "$command" "window=$1" ;;
    press) [[ $# -eq 2 ]] || usage; ctl press "window=$1" "label=$2" ;;
    shot) [[ $# -eq 2 ]] || usage; ctl shot "window=$1" "path=$2" ;;
    ctl) ctl "$@" ;;
    smoke) exec "$root/scripts/dev-smoke.sh" "$@" ;;
    *) usage ;;
esac
