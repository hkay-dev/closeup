---
type: reference
summary: The user journeys of Android Webcam (core, regular, rare), each with who and where, steps and what it touches, plus where features share state or a moment. The map a bug bash walks.
---

# Journeys

Built on 2026-10-21 at d531cd4 from PRODUCT.md, README.md, decisions.md, notes.md, wireless-latency-session.md and the app itself; read again at cdb3e7d, where no journey changed. A bug bash (see the `bug-bash` skill) walks these. Update it when a feature lands.

Who is always Harsha, on the Mac, with a Samsung phone on a mount over USB-C, unless a step says otherwise. "The menu" is the menu bar item's menu.

## Start the webcam and join a call (core)
Who and where: Harsha on the Mac, a few minutes before a call, phone plugged in.
Steps:
1. The camera icon is in the menu bar (outline `camera`). Open the menu: the header says "Ready" with "<model> is ready"; the main item says "Start Webcam".
2. Choose Start Webcam. Icon becomes `camera.badge.ellipsis` and the header "Starting <model>", then `camera.fill` with "Live 0:05 · 1080p · 30" and a thumbnail. A "Webcam is live" notification appears on the first start (if Notifications is on).
3. In Chrome (or Zoom, Meet) pick "OBS Virtual Camera". The phone's picture shows.
4. Talk for the length of the call; the header keeps the live time, phone temperature and battery.
5. Choose Stop Webcam (or quit). Header "Stopping", then back to "Ready"; the phone's camera closes.
Touches: adb track-devices, the scrcpy server jar pushed to the phone, adb forward, HEVC decode, CoreMediaIO sink stream in the OBS extension, the activity assertion, notifications, saved phone and mode in UserDefaults.

## Stop and quit after the call (core)
Who and where: Harsha on the Mac, right after the call.
Steps:
1. Stop Webcam from the menu; the picture goes, notifications about the run are removed, the phone's server and forward entry go away.
2. Quit from the menu (or Command-Q). The app exits without leaving an adb child or forward behind.
3. Quit while live: the app stops capture first, then exits.
Touches: capture teardown, adb forward and pushed jar, notifications, App Nap activity, the shared ADB server (never stopped).

## Reopen the app and carry on (core)
Who and where: Harsha on the Mac, next day, phone plugged in again, app not running (or running with its icon out of reach).
Steps:
1. Open Android Webcam from Finder, Spotlight or Raycast. The icon appears; setup does not reopen when it was done.
2. The saved phone and mode are selected. The menu says "Ready" and Start Webcam works without touching Setup.
3. Open it again while it runs: the menu opens, or Settings when the icon is unreachable.
Touches: UserDefaults (saved serial, mode, lens, setupShown), the device watcher, applicationShouldHandleReopen, OBS lookup.

## Choose a phone, a mode and a lens (regular)
Who and where: Harsha on the Mac, before or during a call.
Steps:
1. Phone submenu lists plugged-in phones (a phone that hasn't allowed debugging says "allow USB debugging" and is disabled). Pick one.
2. Capture Mode lists 4K · 60, 1080p · 60, 1080p · 30, 1080p · 120; disabled while running.
3. While live, Camera lists the lenses; pick one and the header says "Switching camera" while the call keeps the camera. A lens that can't run the mode goes back to the one that worked, and the header says so ("Back · Main can't run 1080p · 30. The webcam went back to Front.").
4. Zoom In, Zoom Out, Flashlight change the live picture; the flashlight state shows in the menu.
Touches: saved serial, mode and lens in UserDefaults, the phone's camera list, control socket messages.

## Preview window (regular)
Who and where: Harsha on the Mac, checking framing.
Steps:
1. Choose Show Preview; a 16:9 window opens with a veil ("No picture yet") until live, then the picture.
2. Resize; it keeps 16:9. Close and reopen; size and place are remembered.
3. Stop the webcam: the preview clears and the veil returns.
Touches: PreviewView, frame tap shared with the menu header and the sync test, window autosave.

## Check Audio Sync (regular)
Who and where: Harsha on the Mac with the webcam live and his microphone.
Steps:
1. Choose Check Audio Sync. The window names the microphone. With the webcam off it offers Start Webcam.
2. Press Start, clap once. The level meter moves, "Heard the clap" shows, and the result reads "Video N ms behind" with advice.
3. A denied microphone shows an Open Microphone Settings button; no microphone says so.
4. Stop the webcam or lose the phone mid-test: the window says the webcam stopped.
Touches: microphone permission, frame tap, the live state, window shelf.

## Image Settings (regular)
Who and where: Harsha on the Mac, tuning the picture mid-call.
Steps:
1. Choose Image Settings. A window shows exposure, white balance, focus, noise reduction, sharpness (phone) and Mac sharpening.
2. Change values while live; the picture changes. Reset to Automatic returns everything.
3. Settings stick across a lens switch, a mode switch, a reconnect and a restart.
Touches: ImageStore, control messages to the phone, the Mac Core Image sharpening step, saved image state.

## Phone cable comes loose mid-call (regular)
Who and where: Harsha on the Mac in a call, the cable on a mount gets bumped.
Steps:
1. The picture freezes under a veil "Plug the phone back in"; icon shows reconnecting; after about 1.5 s a "Phone disconnected" notification appears. The call keeps the virtual camera.
2. Plug the phone back in. The picture resumes on its own; "Phone reconnected" replaces the disconnected notification.
3. If the stream drops while the phone stays plugged in (its camera server restarted), the veil says "Reconnecting to <model>" and no notification appears.
4. If the phone does not come back, Stop Webcam still works.
Touches: device watcher, reconnect loop, cable notification topic, preview and header veils, image settings, lens and zoom state.

## The phone runs hot (regular)
Who and where: Harsha on the Mac, a long call in 4K.
Steps:
1. Header shows temperature and battery. When hot, one notification with a "Switch to 1080p · 30" button and a menu item of the same kind appear.
2. Choose it: the webcam restarts quietly in 1080p · 30 with no stop notification and the call keeps its camera.
Touches: phone stats polling, heat notification topic, restart path, saved mode.

## Notifications and Settings (regular)
Who and where: Harsha on the Mac.
Steps:
1. Settings shows Launch at login, Start when the phone is plugged in, Notifications and the version line.
2. First Start with Notifications on asks permission once. A denied permission shows a line in Settings saying how to turn it on.
3. Click a notification: the menu opens.
4. Start when plugged in: the webcam starts at launch with the saved phone plugged in, or when the saved phone shows up allowed; never because the menu opened or the switch was turned on. After Stop it waits until the phone has been unplugged for 5 s.
Touches: SMAppService, UNUserNotificationCenter, UserDefaults, autostart blocking.

## Stopped on an error (regular)
Who and where: Harsha on the Mac, something went wrong on the phone.
Steps:
1. Start the webcam while another app on the phone holds the camera, or USB debugging was revoked, or the mode isn't supported.
2. The webcam stops. The header and a "Webcam stopped" notification give one plain sentence and what to do next. No reconnect loop for setup errors.
3. Fix it (close the other app, tap Allow, pick a lower mode) and Start again; it works without relaunching.
Touches: error translation in Capture, the note in the header, the run notification topic.

## OBS opens during capture (regular)
Who and where: Harsha on the Mac, opens OBS by accident, mid-call.
Steps:
1. The header note warns "OBS opened. Don't start its virtual camera while this one runs." Capture keeps going.
2. Quit OBS: the note clears and setup shows OBS closed again.
3. With OBS open and the webcam off, Start says "Quit OBS before starting this camera."
Touches: workspace launch and terminate notifications, setup step "OBS Studio closed", header note.

## Mac sleeps and wakes with the webcam on (regular)
Who and where: Harsha on the Mac, lid closed between calls with the webcam left running.
Steps:
1. Sleep the Mac. Wake it. The stream reconnects within about 20 seconds with no "Phone disconnected" notification.
2. If the phone stayed plugged in the picture resumes; otherwise the cable path runs.
Touches: sleep and wake observers, reconnect loop, the loose cable timer.

## First run and setup (rare)
Who and where: Harsha (or a stranger once it's open source) on a Mac that has never run it.
Steps:
1. Open the app. The Setup window opens by itself once, listing five steps: Android platform tools, OBS camera extension, phone connected over USB, Allow USB debugging, OBS Studio closed. Each pending step has its own buttons (Copy Command, Get Platform Tools, Open OBS, Open Login Items, Quit OBS, Show me how).
2. Do each step; the list checks itself every few seconds and the menu header counts "N of 5 setup steps done" with "Next: ...".
3. When all are done the window says "All set" and offers Start Webcam.
4. Close Setup early: the menu's main item reads "Finish Setup…" and reopens it. It does not open again by itself on the next launch.
Touches: adb lookup, CoreMediaIO device lookup, NSWorkspace, System Settings deep links, UserDefaults setupShown.

## Error and recovery without a phone (rare)
Who and where: Harsha on the Mac with no phone, no adb, a phone that never allowed debugging, or adb hung.
Steps:
1. No phone: the Phone submenu says "No USB phone connected" and Start Webcam is disabled; the header says what to do next.
2. adb missing: setup says to install platform tools; `--diagnose` says so and exits 1.
3. A phone shows as "(allow USB debugging)" until it is approved, then becomes selectable without relaunching. One that adb lists as offline or connecting shows "(connecting, unplug and replug if it stays)".
4. adb track-devices fails: the app says "adb isn't working" and keeps retrying.
Touches: DeviceWatcher, setup model, the menu's phone items.

## Crash cleanup on next launch (rare)
Who and where: Harsha on the Mac after the app was killed or the Mac logged out mid-capture.
Steps:
1. The phone still has the pushed jar and an adb forward entry.
2. Launch the app again. It removes what the earlier session recorded, and only that, and never stops the ADB server.
Touches: the session record, adb forward and shell child, shared ADB server.

## Wireless debugging session (rare)
Who and where: Harsha at the latency session, with the hidden switch on.
Steps:
1. `defaults write com.harsha.android-webcam wirelessAdb -bool true` (or `ANDROID_WEBCAM_WIRELESS=1`), launch.
2. The phone on wireless debugging appears in the Phone menu; capture logs a line per second to the `wireless-latency` category.
3. Off by default: with the switch off, wireless entries are hidden and the menu says "No USB phone connected".
Touches: Wireless.swift, DeviceWatcher parsing, `--diagnose` wireless fields.

## Headless diagnose and probe (rare)
Who and where: Harsha or an agent in a shell.
Steps:
1. `AndroidWebcam --diagnose` prints JSON with usb_devices, bundled server, adb path, OBS extension state, HEVC support, wireless fields; it starts no camera or preview.
2. `--probe-hevc <file>` decodes a sample; bad arguments exit 1. The sample is Annex B HEVC with access-unit delimiters (`ffmpeg -f lavfi -i testsrc=size=1280x720:rate=30 -t 2 -c:v libx265 -x265-params aud=1 -pix_fmt yuv420p -f hevc sample.h265`). Two samples joined end to end at different sizes decode as one stream and report the last size. A sample without delimiters, without parameter sets or cut off exits 1 with one plain sentence.
3. `--diagnose` lists every wireless phone adb knows under `wireless_devices` whether or not the switch is on (`adb connect 127.0.0.1:<emulator adb port>` makes one without a phone). An emulator never appears under `usb_devices`: its adb line has no `usb:` field, so the both-transports dedupe needs a real phone.
Touches: ADB, VirtualCamera lookup, VideoToolbox.

## Where features meet

- **Start when plugged in against Stop:** after Stop the saved phone must not start again until it is unplugged; an unplug that only looks like a failed adb stream must not unblock it.
- **Setup incomplete against Launch at login and Start when plugged in:** the app launches at login with Setup unfinished; auto start must not fire.
- **Mode menu disabled while running against the cool-down switch:** the heat button restarts in 1080p · 30 while the menu mode stays locked; the saved mode then changes under the user.
- **Cool-down restart against Stop, Quit and a cable drop:** a Stop or Quit during the restart cancels it; a drop during it must not show "Phone disconnected" or a stop notification.
- **Lens switch against zoom, flashlight and image settings:** the torch resets on a switch; zoom and image settings should carry over; a lens that can't run the mode is not remembered.
- **Reconnect against image settings, lens and zoom:** after the stream comes back the phone's camera setup should match what the menu shows.
- **Reconnect against Mac sleep:** the quiet window after wake against a phone that really was unplugged.
- **Check Audio Sync against Stop, a cable drop and a lens switch:** the test ends with a clear message and the window doesn't stay on "Listening".
- **Notification topics against each other:** one notification each for run, cable and heat; "Webcam stopped" must not sit next to a newer "Webcam is live"; stopping removes ones that no longer apply.
- **OBS opened during capture against the next start:** the warning clears when OBS quits, and Start stays blocked while it is open.
- **Preview, header thumbnail and sync test share one frame tap:** closing the preview must not freeze the header or the test.
- **Second phone against the saved phone:** the saved phone wins whenever plugged in; a second phone doesn't steal the session or the saved serial.
- **Wireless switch against USB only:** a phone on both transports shows once, as wireless, only with the switch on.
- **Reopen against a running session and Settings:** reopening with the icon out of reach opens Settings, and nothing else moves.

## Driving notes (no phone)

- The GUI needs a throwaway macOS VM (the app is a menu bar item, and `--diagnose` and `--probe-hevc` are the only headless entries). A clone needs OBS.app to get the camera extension. `macvm install-app "$vm" /Applications/OBS.app` from the Mac works (about 1 minute), then OBS's Start Virtual Camera raises "would like to use a new camera extension", Open System Settings, the toggle, the account password, Done. Doing that in every clone takes about 8 minutes of a 20 minute hold; use the base below instead.
- **The OBS base:** `macOS 27 Android Webcam Base` is `macOS 27 Base` plus OBS Studio 32.2.2 in /Applications with its camera extension approved (`systemextensionsctl list` shows `com.obsproject.obs-studio.mac-camera-extension` as `[activated enabled]`), OBS's permission screen continued without granting anything, OBS's update check answered Don't Check, and OBS quit. It has no Android Webcam app, no adb, no account and no credential. Its snapshot is `OBS 32.2.2 with camera extension approved`. Clone it with `macvm up <owner> --base "macOS 27 Android Webcam Base"` (or `MACVM_BASE`), then `macvm install-app` the build and `vmpal cp` the Mac's adb to `Library/Android/sdk/platform-tools/adb` (where the app looks first in the VM; `chmod +x` it). `--diagnose` in such a clone reports `obs_camera_installed: true`; without adb it exits 1 on the install line before printing. Going Live in a clone from it needs an emulator and was not re-proved here. Never test in the base itself. The first-run Setup journey still needs the plain `macOS 27 Base`, where the extension is not approved.
- On this Mac (no VM): the off-screen dev instance with the AVD `Webcam_A` on port 5920 and `ADB=scripts/fault-adb` drives every journey except real banners, Mac sleep and a microphone (docs/dev-automation.md). Its camera ids are 0 (Back, no 1080p) and 1 (Front); seed `lensID=1` and the lens list at `start`. In the VM the older stand-in was an Android 36 emulator whose camera ids are 1 (front) and 10 (back), so `defaults write com.harsha.android-webcam lensID -string 1` there. The VM reaches it through a `socat` relay on the bridge address into the emulator's adb port, then `adb connect` in the VM, with the wireless switch on.
- With the Mac's load near 70 to 100 the emulator's camera can fail most frames. At step 3 (load about 90) a 1080p stream still ran for minutes and the Live clock kept counting.
- A microphone needs `macvm vmpal set <vm> --microphone on`, which records the Mac's real microphone and needs Harsha's say-so. Without it Check Audio Sync stays on "No microphone found".
- Heat works: `adb shell dumpsys battery set temp 450` (tenths of a degree) shows "113°F" in the header within 10 seconds. In 1080p / 30 (the cool mode) there is no switch item, only a notification; in 1080p / 60 the menu shows "Switch to 1080p • 30 to cool down" and choosing it restarts quietly at 1080p • 30 with the item gone. `dumpsys battery reset` puts it back.
- The emulator's camera app does not take camera 1 from the scrcpy server, so "Another app on the phone is using the camera" can't be driven there. Killing the emulator mid-capture gives "Plug the phone back in" with "Reconnecting"; Stop then works and leaves the menu on "Next: allow USB debugging on the phone", because adb lists the dead emulator as `offline`.
- The stale adb forward after `kill -9` of the app is removed by the next launch, and the adb shell child dies with the app.
