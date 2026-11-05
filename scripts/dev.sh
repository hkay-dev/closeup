#!/usr/bin/env bash
# Off-screen dev instance of Closeup for agents and scripts (docs/dev-automation.md).
# The instance has its own defaults, no status item, windows parked below the desktop, and a control
# socket that only exists because CLOSEUP_DEV_DIR is set. Nothing shows on screen.
#
#   scripts/dev.sh                       build (under qm) and start the instance, like build then start
#   scripts/dev.sh build                 build the app, debug, into build/debug/Closeup.app (scripts/build-app.sh)
#   scripts/dev.sh start [KEY=VALUE ...] start the instance; prints its directory. KEY=VALUE (KEY:=JSON) seeds its defaults
#   scripts/dev.sh stop                  choose Quit, wait for the process, remove the directory
#   scripts/dev.sh state                 header text, menu items, open windows
#   scripts/dev.sh menu                  header text and menu items only
#   scripts/dev.sh choose TITLE          choose a menu item: "Settings", "Start Webcam", "Live Controls", ...
#   scripts/dev.sh open WINDOW           setup, settings, controls, sync or preview
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
# Commands find the instance through $CLOSEUP_DEV_DIR, else the one `start` last printed.
# Take the desktop for anything that screenshots: qm with desktop NAME -- scripts/dev.sh smoke
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="${CLOSEUP_APP:-$root/build/debug/Closeup.app}"
# One instance per checkout, so worktrees can each run their own.
pointer="${XDG_CACHE_HOME:-$HOME/.cache}/closeup/dev-current-$(printf %s "$root" | shasum | cut -c1-10)"

die() {
    echo "dev.sh: $*" >&2
    exit 2
}

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

current_dir() {
    local dir="${CLOSEUP_DEV_DIR:-}"
    [[ -n "$dir" ]] || { [[ -f "$pointer" ]] && dir="$(<"$pointer")"; }
    [[ -n "$dir" && -S "$dir/control.sock" ]] || die "no dev instance running. Run scripts/dev.sh start."
    printf '%s\n' "$dir"
}

ctl() {
    python3 "$root/scripts/dev-ctl.py" "$(current_dir)" "$@"
}

start() {
    [[ -x "$bundle/Contents/MacOS/Closeup" ]] || die "no app at $bundle. Run scripts/dev.sh build, or set CLOSEUP_APP."
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
    # open -g -j -n starts a background instance that never takes the front, the keyboard or a Space; a bare binary
    # from a shell would (docs/dev-automation.md). open can't hand back a pid, so it comes from the socket's owner.
    : >"$dir/app.log"
    open -g -j -n --stdout "$dir/app.log" --stderr "$dir/app.log" --env "CLOSEUP_DEV_DIR=$dir" "$bundle"
    local tries=0
    until python3 "$root/scripts/dev-ctl.py" "$dir" ping >/dev/null 2>&1; do
        (( ++tries < 100 )) || { cat "$dir/app.log" >&2; die "the control socket never answered. Log: $dir/app.log"; }
        sleep 0.2
    done
    lsof -t "$dir/control.sock" | head -n 1 >"$dir/pid"
    [[ -s "$dir/pid" ]] || die "the app answered but its pid wasn't found. Log: $dir/app.log"
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
if [[ -z "$command" ]]; then
    # Bare: build under the qm build gate (plain when qm is absent), then start the instance.
    if command -v qm >/dev/null 2>&1; then qm with build android-webcam -- "$root/scripts/dev.sh" build >&2; else "$root/scripts/dev.sh" build >&2; fi
    start
    exit
fi
shift
case "$command" in
    build) CLOSEUP_CONFIG=debug exec "$root/scripts/build-app.sh" ;;
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
