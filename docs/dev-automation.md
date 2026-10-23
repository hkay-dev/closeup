---
type: feature
summary: An off-screen dev instance of Closeup that an agent drives from a terminal - read the menu header and items, choose items, read and press controls in Setup, Settings, Live Controls and Check Audio Sync, save window PNGs - with isolated defaults and nothing on Harsha's screen.
covers:
  - Sources/Closeup/DevControl.swift
  - Sources/Closeup/DevAccessibility.swift
  - Sources/Closeup/App.swift
  - Sources/Closeup/Windows.swift
  - Sources/Closeup/Hotkey.swift
  - Sources/Closeup/Diagnostics.swift
  - Sources/Closeup/Installer.swift
  - Sources/Closeup/ControlsPanel.swift
  - scripts/dev.sh
  - scripts/dev-ctl.py
  - scripts/dev-smoke.sh
  - scripts/dev-windows.swift
  - scripts/fault-adb
---

# Dev automation (off screen)

Built for kata:android-webcam#2a6e. Before it, every GUI journey needed one of the Mac's two macOS VM places. Now an agent on this Mac can walk the menu, Setup, Settings, Live Controls and Check Audio Sync from a terminal while nothing shows on Harsha's screen. The pattern is the one Ramble and Vesper use: a dev instance with its own settings and a control socket, windows parked below the desktop, and `screencapture -l` for pictures.

## The switch

The control path exists only when `CLOSEUP_DEV_DIR` names an absolute directory (short, such as `/tmp/awdev.XXXXXX`: the socket path has to fit in 103 bytes). A normal launch has no such variable, so it opens no socket, keeps its status item and windows, and reads its real defaults. `--diagnose` and `--probe-hevc` don't look at it. `scripts/dev.sh start` makes the directory and sets the variable.

## What dev mode changes

| Area | Normal launch | Dev instance |
| --- | --- | --- |
| Settings | `UserDefaults.standard` (`com.harsha.closeup`) | Its own suite, `com.harsha.closeup.dev.<dir name>`, emptied at launch and deleted at quit. Every read and write goes through `Prefs.defaults`, including the SwiftUI toggles and the hidden wireless switch (the `CLOSEUP_WIRELESS` variable still wins). |
| Menu bar | A status item | None at all. A hidden status item would still be saved in the real app's defaults, so none is created. The menu is the same `NSMenu`, read and chosen through the socket. |
| Windows | Brought forward and activated | Parked one level below the desktop (`CGWindowLevelForKey(.desktopWindow) - 1`) with `orderFrontRegardless`. The wallpaper covers them, the app never activates, nothing takes focus. The Live Controls panel loses its floating level the same way. The Preview window and the Live Controls panel skip their saved frames, so no `NSWindow Frame Preview` or `NSWindow Frame LiveControls` lands in the real defaults. |
| Notifications | macOS banners | Recorded, not posted (`effects`). |
| Buttons that act outside the app | Open OBS, About platform tools, Get OBS from obsproject.com, Quit OBS, Open Login Items, Open Microphone Settings, the Launch at login switch, Copy Diagnostics | Recorded, not done: no URL opened, no login item registered, no app quit, nothing on the pasteboard. Copy Diagnostics records the whole report as a `pasteboard` effect. |
| The Live Controls shortcut (⌃⌥⌘L) | Registered with Carbon `RegisterEventHotKey`, so it works from any app with no Accessibility permission | Never registered, since it would fire on the real Mac. Turning the Settings switch on or off records `hotkey` (`register ⌃⌥⌘L`, `unregister ⌃⌥⌘L`), and `ctl hotkey` runs what the press would. The menu's Live Controls… item still shows the key (`"key": "l"`; the modifiers aren't in the reply). |
| Setup's downloads | Download Platform Tools unzips into `~/Library/Application Support/<app name>/platform-tools`; Download OBS copies OBS.app into `/Applications` | Done for real, into `<dir>/platform-tools` and `<dir>/Applications/OBS.app`, so `stop` deletes them. The Finder window for a read-only `/Applications` is recorded as `open-url`. |
| A Mac with nothing installed | | `CLOSEUP_DEV_BARE=1` in the environment of `start`: adb is looked for only in `<dir>/platform-tools`, OBS only in `<dir>/Applications`, and OBS's camera counts as off, so Setup shows its first steps on this Mac too. |
| OBS extension relaunch | `relaunchForExtension` opens a fresh copy and quits | Skipped. |
| A short screen | Live Controls and Setup cap their height to the screen's visible frame and scroll the controls under Start, or Setup's steps | `start devScreenHeight:=700` makes both act as if the screen had 700 pt of room, to check the scrolling without a small display. |
| Session record | `~/Library/Application Support/com.harsha.closeup/session.json` | `<dir>/session.json`, so the dev instance never cleans up after the real app's phone session. |

## Commands

Run `scripts/build-app.sh` once (or `scripts/dev.sh build`), then use `scripts/dev.sh`. Every command prints JSON and exits 1 when the reply says `"ok": false`. Take the desktop for anything that screenshots: `qm with desktop NAME -- scripts/dev.sh smoke`. A dev instance runs next to the real app without trouble; both use the one adb server.

| Command | What it does |
| --- | --- |
| `start [KEY=VALUE ...]` | Starts the instance in the background, waits for the first setup check, prints its directory. Later commands find it through `CLOSEUP_DEV_DIR` or the directory `start` last printed. `KEY=VALUE` (a string) or `KEY:=JSON` seeds its defaults before launch through `<dir>/seed.json`; arrays and objects are stored as JSON data, as the app saves them. For example `start lensID=1 phoneSerial=emulator-5920 startOnPlugIn:=true 'lenses.emulator-5920:=[{"id":"0","label":"Back · Main","facing":"back"},{"id":"1","label":"Front","facing":"front"}]'`. |
| `stop` | Chooses Quit, waits for the process, removes the directory and the dev defaults. |
| `state` | `header` (the lines the menu header shows, such as `3 of 6 setup steps done` and `Next: plug in your phone with a USB cable.`), `menu`, `windows`, `ready`. |
| `menu` | Header and menu items: title, enabled, hidden, check state, key, submenus. |
| `choose TITLE` | Chooses an item as a click would. Matches the full title, the title without its ellipsis (`Settings`), a unique prefix (`Quit`), or a submenu path (`Capture Mode/1080p · 60 fps`). `Setup` matches Finish Setup…. Refuses an item that is missing, hidden or disabled and says why, with the header. Reply: the item, the header after, open windows, effects. |
| `open WINDOW` / `close WINDOW` | `setup`, `settings`, `controls` (Live Controls), `sync` or `preview`. Setup is only in the menu as Finish Setup… while a step is open, so `open setup` is the way in once everything is done. Live Controls fades in and out over about 0.2 s, so `close controls` replies while the panel is still listed; `ctl hotkey` waits for the fade. |
| `windows` | Open windows: `id`, title, `windowNumber`, `level`, `parked`, frame. |
| `text WINDOW` | What the window shows, one line per element. Controls read `[CheckBox] Notifications = 1` (1 is on), `[Button] Reset to Automatic`, `[DisclosureTriangle] Show me how = 0`. Each Setup step starts with its group's label, such as `Step 1, Get Android platform tools, done` (or `do this next`, `not done yet`). |
| `tree WINDOW` | The accessibility tree as JSON (role, label, value, help, enabled). |
| `press WINDOW LABEL` | Presses the one enabled control with that label (exact, then case-blind, then a part of it); says which controls exist when none or several match. Reply: what was pressed and the window's text afterwards. |
| `shot WINDOW PATH` | Saves the window as a PNG with `screencapture -x -o -l <windowNumber>`; if that comes back empty it draws the window's own view and says so under `notes`. |
| `effects` | What the instance would have done outside its windows: `notification`, `setup-action`, `open-url`, `launch-at-login`, `open-login-items`, `hotkey`, `pasteboard` (the Copy Diagnostics report). |
| `defaults` | The dev suite's values, to check that a toggle landed there. |
| `ctl OP key=value key:=json` | Any operation. |
| `ctl hotkey` | Does what ⌃⌥⌘L does: opens Live Controls, or closes it when it's open. Reply: open windows. |
| `ctl sync-phase phase=P ...` | Puts Check Audio Sync in a state without a phone or a clap, to look at it: `phase=listening level:=0.6 progress:=0.4 heard:=false`, `phase=result lagMs:=118`, `phase=failed text='...' microphone:=true`, `phase=idle`. It changes only the window; the Start button still needs a live webcam. |
| `smoke [DIR]` | The whole journey below, with checks. |

`WINDOW` is the id from `windows`. Sliders and segmented pickers in Live Controls can be read with `text` and `tree`; `press` covers buttons, check boxes, radio buttons and disclosure triangles. In Live Controls that's `Start Webcam` or `Finish Setup…` (shown only while the webcam isn't running; there's no Stop there), the lens chips (by lens name, such as `Front`), `Zoom in`, `Zoom out`, `Flashlight`, the white balance chips (`Auto white balance`, `Daylight`, `Cloudy`, `Incandescent`, `Fluorescent`), `Continuous focus`, `Locked focus`, `More` and `Reset to Automatic`. A press is one click, so it can't show the zoom buttons repeating while held. Settings shows one pane at a time, so `press settings Phone` (or `General`, `Live Controls`, `Help`) picks the pane first; it opens on General.

## Smoke journey

`qm with desktop NAME -- scripts/dev.sh smoke DIR` starts the instance, reads the header and menu, opens Setup (Finish Setup…) and Settings, reads both, presses "Start when the phone is plugged in", checks it in the dev defaults and that the real `startOnPlugIn` didn't change, opens Live Controls and Check Audio Sync and reads them, saves `setup.png`, `settings.png`, `controls.png` and `sync.png`, chooses Start Webcam and prints the refusal, checks the windows are parked, takes `screencapture -x` of the main display before and after, and quits. It exits 0 when every check passed.

With no phone the menu's main action is Finish Setup…, so `choose "Start Webcam"` is refused with `No menu item matches "Start Webcam"` and the item list and header. That is what a user sees too: there is nothing to click. The script skips that step when a phone is connected and Start Webcam is enabled, because the instance would then start the real camera.

## Proof that nothing shows

- The control reply gives every window's `level`; `parked` is true when it sits below `CGWindowLevelForKey(.desktopWindow)`.
- `swift scripts/dev-windows.swift windows PID` lists the same windows from `CGWindowListCopyWindowInfo`, and `visible PID` exits 1 if a window over 30 points high sits at or above the desktop level. On 2026-10-21 the instance had two windows, both at layer -2147483624, and no status item window.
- `screencapture -x` of the main display before and after the smoke journey differed in 0.01% of the pixels below the menu bar (`dev-windows.swift diff A B`). The menu bar clock is skipped.

## A phone stand-in: an emulator and `scripts/fault-adb`

Start Webcam, the lens, zoom and flashlight items, a hot phone and the error journeys run against an emulator with `ADB=$PWD/scripts/fault-adb` in the environment that starts the instance. `fault-adb` runs the real adb and bends what it says, from rules in `/tmp/fault-adb/faults` (`FAULT_ADB_FAULTS` moves it) that it reads on every call and every change, so editing the file mid-run plugs, unplugs and breaks things live. Every call goes to `calls.log` next to the rules, which shows what the app ran and when. The rules are in the script's header; the ones the 2026-10-22 pass used:

| Rule | Drives |
| --- | --- |
| `usb emulator-5920` | the emulator passes the app's USB filter, without the wireless switch |
| `hide emulator-5920` (with `adb shell pkill -f com.genymobile.scrcpy` to end the stream) | a pulled cable; removing the line plugs it back in |
| `device R5CY11B8DHD unauthorized usb:2-1` | a second phone, one that hasn't allowed debugging, or `offline` |
| `device adb-emulator-5920-Xy12Ab._adb-tls-connect._tcp device ...` plus `alias` to the emulator | one phone on USB and wireless (with `CLOSEUP_WIRELESS=1`) |
| `server-error Camera error CAMERA_IN_USE (4): ...` | another app holding the camera, at start or on a reconnect |
| `hang forward tcp:0`, `delay 8 scid=` | a hung adb at Start, Stop and Quit; a slow server start |
| `track-exit` | adb not working |

The emulator is the AVD `Webcam_A` (Android 36, front and back cameras emulated) on port 5920, booted inside the `emu` line (repo `AGENTS.md`). Its camera 1 (Front) runs 1080p at 30 and 60; camera 0 (Back) can't run 1080p, which makes a lens switch that fails. Neither runs 4K or 120 fps, which drives the mode errors. `dumpsys battery set temp 450` makes it hot.

## README screenshots

The PNGs in `docs/assets/` (`setup.png`, `setup-done.png`, `live-controls.png`, `settings.png`, `audio-sync.png`) are `shot`s of the dev instance, retaken on 2026-10-22; `settings.png` was retaken on 2026-10-23 for the new name, and `setup.png` is a window crop from a macOS VM on a fresh install. One thing keeps them free of this Mac's details:

- A phone name. The emulator lists as `Android SDK built for arm64`. Leave out its `usb` rule and list it under a made-up name instead: `device 3A281FDJH00XYZ device usb:1-1 product:shiba model:Pixel_8 device:shiba` and `alias 3A281FDJH00XYZ emulator-5920`, with `lenses.3A281FDJH00XYZ` seeded. Hide any other phone adb lists (`hide SERIAL`).

The emulator's camera shows a blocky test picture, so Live Controls is shot in the Ready state. Check Audio Sync is shot while live (no Start Webcam row) after `ctl sync-phase phase=result lagMs:=118`. Setup mid-way is a separate `CLOSEUP_DEV_BARE=1` instance.

## Limits

- The dev instance records notifications rather than posting them, so it can't show that one replaces or withdraws another; that needs the bundled app.
- An off-screen window can't be captured, so parking is below the desktop level rather than off the display. Ramble found parked windows join a full-screen Space; this app hasn't been checked for that.
- The accessibility walk reads this process through `AXUIElementCreateApplication(getpid())`, which AppKit answers in process. It needs no Accessibility permission. SwiftUI builds a window's tree on the first request, so `text` waits up to half a second for a window that just opened.
- A window can't be dragged, resized or minimized, and there are no key presses or sliders; the instance posts no events.

## Where it lives

`DevControl.swift` has the switch (`DevMode`), the socket and the operations. `DevAccessibility.swift` has the walk and the press. The hooks are `Prefs.defaults` and `bringForward` in `Windows.swift`, and `startDevControl`, the optional status item, the notification and relaunch guards in `App.swift`. `scripts/dev-ctl.py` is the socket client.
