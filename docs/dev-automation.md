---
type: feature
summary: An off-screen dev instance of Android Webcam that an agent drives from a terminal - read the menu header and items, choose items, read and press controls in Setup, Settings, Image Settings and Check Audio Sync, save window PNGs - with isolated defaults and nothing on Harsha's screen.
covers:
  - Sources/AndroidWebcam/DevControl.swift
  - Sources/AndroidWebcam/DevAccessibility.swift
  - Sources/AndroidWebcam/App.swift
  - Sources/AndroidWebcam/Windows.swift
  - scripts/dev.sh
  - scripts/dev-ctl.py
  - scripts/dev-smoke.sh
  - scripts/dev-windows.swift
---

# Dev automation (off screen)

Built for kata:android-webcam#2a6e. Before it, every GUI journey needed one of the Mac's two macOS VM places. Now an agent on this Mac can walk the menu, Setup, Settings, Image Settings and Check Audio Sync from a terminal while nothing shows on Harsha's screen. The pattern is the one Ramble and Vesper use: a dev instance with its own settings and a control socket, windows parked below the desktop, and `screencapture -l` for pictures.

## The switch

The control path exists only when `ANDROID_WEBCAM_DEV_DIR` names an absolute directory (short, such as `/tmp/awdev.XXXXXX`: the socket path has to fit in 103 bytes). A normal launch has no such variable, so it opens no socket, keeps its status item and windows, and reads its real defaults. `--diagnose` and `--probe-hevc` don't look at it. `scripts/dev.sh start` makes the directory and sets the variable.

## What dev mode changes

| Area | Normal launch | Dev instance |
| --- | --- | --- |
| Settings | `UserDefaults.standard` (`com.harsha.android-webcam`) | Its own suite, `com.harsha.android-webcam.dev.<dir name>`, emptied at launch and deleted at quit. Every read and write goes through `Prefs.defaults`, including the SwiftUI toggles and the hidden wireless switch (the `ANDROID_WEBCAM_WIRELESS` variable still wins). |
| Menu bar | A status item | None at all. A hidden status item would still be saved in the real app's defaults, so none is created. The menu is the same `NSMenu`, read and chosen through the socket. |
| Windows | Brought forward and activated | Parked one level below the desktop (`CGWindowLevelForKey(.desktopWindow) - 1`) with `orderFrontRegardless`. The wallpaper covers them, the app never activates, nothing takes focus. The Preview window skips its saved frame, so no `NSWindow Frame Preview` lands in the real defaults. |
| Notifications | macOS banners | Recorded, not posted (`effects`). |
| Buttons that act outside the app | Copy Command, Open OBS, Get Platform Tools, Quit OBS, Open Login Items, Open Microphone Settings, the Launch at login switch | Recorded, not done: no pasteboard write, no URL opened, no login item registered, no app quit. |
| OBS extension relaunch | `relaunchForExtension` opens a fresh copy and quits | Skipped. |
| Session record | `~/Library/Application Support/com.harsha.android-webcam/session.json` | `<dir>/session.json`, so the dev instance never cleans up after the real app's phone session. |

## Commands

Run `scripts/build-app.sh` once (or `scripts/dev.sh build`), then use `scripts/dev.sh`. Every command prints JSON and exits 1 when the reply says `"ok": false`. Take the desktop for anything that screenshots: `qm with desktop NAME -- scripts/dev.sh smoke`. A dev instance runs next to the real app without trouble; both use the one adb server.

| Command | What it does |
| --- | --- |
| `start` | Starts the instance in the background, waits for the first setup check, prints its directory. Later commands find it through `ANDROID_WEBCAM_DEV_DIR` or the directory `start` last printed. |
| `stop` | Chooses Quit, waits for the process, removes the directory and the dev defaults. |
| `state` | `header` (the lines the menu header shows, such as `3 of 5 setup steps done` and `Next: plug in your phone with a USB cable.`), `menu`, `windows`, `ready`. |
| `menu` | Header and menu items: title, enabled, hidden, check state, key, submenus. |
| `choose TITLE` | Chooses an item as a click would. Matches the full title, the title without its ellipsis (`Settings`), a unique prefix (`Quit`), or a submenu path (`Capture Mode/1080p / 60 fps`). `Setup` matches Finish Setup…. Refuses an item that is missing, hidden or disabled and says why, with the header. Reply: the item, the header after, open windows, effects. |
| `open WINDOW` / `close WINDOW` | `setup`, `settings`, `image`, `sync` or `preview`. Setup is only in the menu as Finish Setup… while a step is open, so `open setup` is the way in once everything is done. |
| `windows` | Open windows: `id`, title, `windowNumber`, `level`, `parked`, frame. |
| `text WINDOW` | What the window shows, one line per element. Controls read `[CheckBox] Notifications = 1` (1 is on), `[Button] Reset to Automatic`, `[DisclosureTriangle] Show me how = 0`. Step marks read `[Image] Selected` for done and a circle name for pending. |
| `tree WINDOW` | The accessibility tree as JSON (role, label, value, help, enabled). |
| `press WINDOW LABEL` | Presses the one enabled control with that label (exact, then case-blind, then a part of it); says which controls exist when none or several match. Reply: what was pressed and the window's text afterwards. |
| `shot WINDOW PATH` | Saves the window as a PNG with `screencapture -x -o -l <windowNumber>`; if that comes back empty it draws the window's own view and says so under `notes`. |
| `effects` | What the instance would have done outside its windows: `notification`, `setup-action`, `open-url`, `launch-at-login`, `open-login-items`. |
| `defaults` | The dev suite's values, to check that a toggle landed there. |
| `ctl OP key=value key:=json` | Any operation. |
| `smoke [DIR]` | The whole journey below, with checks. |

`WINDOW` is the id from `windows`. Sliders and pop-up menus in Image Settings can be read with `text` and `tree`; `press` covers buttons, check boxes, radio buttons and disclosure triangles.

## Smoke journey

`qm with desktop NAME -- scripts/dev.sh smoke DIR` starts the instance, reads the header and menu, opens Setup (Finish Setup…) and Settings, reads both, presses "Start when the phone is plugged in", checks it in the dev defaults and that the real `startOnPlugIn` didn't change, saves `setup.png` and `settings.png`, chooses Start Webcam and prints the refusal, checks the windows are parked, takes `screencapture -x` of the main display before and after, and quits. It exits 0 when every check passed.

With no phone the menu's main action is Finish Setup…, so `choose "Start Webcam"` is refused with `No menu item matches "Start Webcam"` and the item list and header. That is what a user sees too: there is nothing to click. The script skips that step when a phone is connected and Start Webcam is enabled, because the instance would then start the real camera.

## Proof that nothing shows

- The control reply gives every window's `level`; `parked` is true when it sits below `CGWindowLevelForKey(.desktopWindow)`.
- `swift scripts/dev-windows.swift windows PID` lists the same windows from `CGWindowListCopyWindowInfo`, and `visible PID` exits 1 if a window over 30 points high sits at or above the desktop level. On 2026-10-21 the instance had two windows, both at layer -2147483624, and no status item window.
- `screencapture -x` of the main display before and after the smoke journey differed in 0.01% of the pixels below the menu bar (`dev-windows.swift diff A B`). The menu bar clock is skipped.

## Limits

- Start Webcam, the lens, zoom and flashlight items, a hot phone and a live sync check need a phone or a stand-in for `adb`. The app finds `adb` through `$ADB`, so a script that answers `track-devices` and fails `push` would drive the Stopped on an error journey; none exists yet.
- An off-screen window can't be captured, so parking is below the desktop level rather than off the display. Ramble found parked windows join a full-screen Space; this app hasn't been checked for that.
- The accessibility walk reads this process through `AXUIElementCreateApplication(getpid())`, which AppKit answers in process. It needs no Accessibility permission. SwiftUI builds a window's tree on the first request, so `text` waits up to half a second for a window that just opened.
- A window can't be dragged or resized, and there are no key presses or sliders; the instance posts no events.

## Where it lives

`DevControl.swift` has the switch (`DevMode`), the socket and the operations. `DevAccessibility.swift` has the walk and the press. The hooks are `Prefs.defaults` and `bringForward` in `Windows.swift`, and `startDevControl`, the optional status item, the notification and relaunch guards in `App.swift`. `scripts/dev-ctl.py` is the socket client.
