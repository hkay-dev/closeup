#!/usr/bin/env bash
# The Mac journey, driven off screen, with checks: start the dev instance, read the header, open Setup and
# Settings, read their text, toggle one Settings control in the isolated defaults, save both windows as PNGs,
# choose Start Webcam with no phone and read what comes back, then Quit. Throughout it checks that no window of
# the app sits at or above the desktop level and that the real app's defaults didn't change.
#
#   qm with desktop NAME -- scripts/dev.sh smoke [DIR]     DIR keeps the PNGs and logs (default: a new /tmp folder)
#
# Needs the built app (scripts/dev.sh build). Exits 0 when every check passed.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dev="$root/scripts/dev.sh"
out="${1:-$(mktemp -d /tmp/awdev-smoke.XXXXXX)}"
mkdir -p "$out"
failures=0
domain=com.harsha.android-webcam

say() { printf '%s\n' "$*"; }
check() {
    if [[ "$1" == ok ]]; then say "PASS  $2"; else say "FAIL  $2"; failures=$((failures + 1)); fi
}
ok_if() { # ok_if "description" command...
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then check ok "$description"; else check bad "$description"; fi
}

real_before="$(defaults read "$domain" startOnPlugIn 2>&1)"
screencapture -x "$out/desktop-before.png"

dir="$("$dev" start)" || { say "FAIL  the dev instance didn't start"; exit 1; }
pid="$(<"$dir/pid")"
say "dev instance: $dir (pid $pid)"
trap '"$dev" stop >/dev/null 2>&1 || true' EXIT

# Header and menu
menu="$("$dev" menu)"
say "$menu" >"$out/menu.json"
say "header: $(jq -r '.header | join(" / ")' <<<"$menu")"
say "menu: $(jq -r '[.menu[] | select(.title) | .title + (if .enabled then "" else " (disabled)" end)] | join(" | ")' <<<"$menu")"
ok_if "the header has text" jq -e '.header | length > 0' <<<"$menu"
ok_if "the menu lists Settings and Quit" jq -e '[.menu[].title // empty] | (map(startswith("Settings")) | any) and (map(startswith("Quit")) | any)' <<<"$menu"

# Setup: open it from the menu when the main action is Finish Setup, else directly
"$dev" choose "Setup" >/dev/null 2>&1 || "$dev" open setup >/dev/null
setup="$("$dev" text setup)"
say "$setup" >"$out/setup-text.json"
say "setup text:"
jq -r '.text[] | "  " + .' <<<"$setup"
ok_if "Setup shows the platform tools step" jq -e '.text | any(test("platform tools"; "i"))' <<<"$setup"

# Settings: read it, toggle one control, check it landed in the isolated defaults
"$dev" choose "Settings" >/dev/null
settings="$("$dev" text settings)"
say "settings text:"
jq -r '.text[] | "  " + .' <<<"$settings"
ok_if "Settings shows the plug-in toggle" jq -e '.text | any(test("phone is plugged in"))' <<<"$settings"
"$dev" press settings "Start when the phone is plugged in" >"$out/press.json"
ok_if "the toggle reached the isolated defaults" jq -e '.values.startOnPlugIn == true or .values.startOnPlugIn == 1' < <("$dev" defaults)
real_after="$(defaults read "$domain" startOnPlugIn 2>&1)"
[[ "$real_before" == "$real_after" ]] && check ok "the real app's startOnPlugIn is unchanged ($real_after)" \
    || check bad "the real app's startOnPlugIn changed from $real_before to $real_after"

# Image Settings and Check Audio Sync: read both
"$dev" choose "Image Settings" >/dev/null
image="$("$dev" text image)"
say "image settings text:"
jq -r '.text[] | "  " + .' <<<"$image"
ok_if "Image Settings shows Reset to Automatic" jq -e '.text | any(test("Reset to Automatic"))' <<<"$image"
"$dev" choose "Check Audio Sync" >/dev/null
sync="$("$dev" text sync)"
say "check audio sync text:"
jq -r '.text[] | "  " + .' <<<"$sync"
ok_if "Check Audio Sync shows its Start button" jq -e '.text | any(test("\\[Button.*\\] Start$"))' <<<"$sync"

# PNGs of all four windows
names=(setup settings image sync)
for name in "${names[@]}"; do
    "$dev" shot "$name" "$out/$name.png" >"$out/shot-$name.json"
    say "shot $name: $(jq -c '{backend, width, height, notes}' "$out/shot-$name.json")"
    ok_if "$name.png is a PNG over 4 KB" bash -c "[[ \$(file -b '$out/$name.png') == PNG* && \$(stat -f %z '$out/$name.png') -gt 4096 ]]"
done

# Start Webcam with no phone
if jq -e '.menu[] | select(.title == "Start Webcam" and .enabled)' <<<"$("$dev" menu)" >/dev/null; then
    say "SKIP  a phone is connected and Start Webcam is enabled, so the no-phone check would start the camera"
else
    if reply="$("$dev" choose "Start Webcam" 2>&1)"; then
        say "Start Webcam answered: $(jq -c '{chose, header}' <<<"$reply")"
        check bad "Start Webcam with no phone should have been refused"
    else
        say "Start Webcam refused: $(jq -r .error <<<"$reply")"
        check ok "Start Webcam with no phone is refused with the reason"
    fi
    say "header after: $(jq -r '.header | join(" / ")' <<<"$("$dev" menu)")"
fi

# Nothing on screen
"$dev" windows | jq -c '.windows[] | {id, parked, level, frame}'
ok_if "every app window reports parked below the desktop" jq -e '.windows | length > 0 and all(.parked)' < <("$dev" windows)
swift "$root/scripts/dev-windows.swift" windows "$pid" 2>/dev/null | sed 's/^/  window server: /'
ok_if "the window server shows no app window at or above the desktop level" swift "$root/scripts/dev-windows.swift" visible "$pid"
screencapture -x "$out/desktop-after.png"
say "desktop pixels that changed (below the menu bar), before to after: $(swift "$root/scripts/dev-windows.swift" diff "$out/desktop-before.png" "$out/desktop-after.png" 2>/dev/null)"

# Setup stays closed once closed, and shot never touches a directory
"$dev" close setup >/dev/null
ok_if "Setup stays closed after close" jq -e '[.windows[].id] | index("setup") == null' < <("$dev" state)
mkdir -p "$out/keep-me" && : >"$out/keep-me/file"
ok_if "shot refuses a directory path" bash -c "! '$dev' shot settings '$out/keep-me' >/dev/null 2>&1"
ok_if "the directory and its file are still there" test -f "$out/keep-me/file"

# Quit
quit="$("$dev" choose Quit)"
ok_if "Quit was accepted" jq -e '.quitting == true' <<<"$quit"
for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$pid" 2>/dev/null; then check bad "the app quit"; else check ok "the app quit"; fi
rm -rf "$dir" "${XDG_CACHE_HOME:-$HOME/.cache}/android-webcam/dev-current"
trap - EXIT

say "files in $out"
if [[ "$failures" -eq 0 ]]; then say "smoke passed"; else say "smoke failed: $failures check(s)"; exit 1; fi
