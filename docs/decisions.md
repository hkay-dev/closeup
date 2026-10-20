---
type: log
summary: One dated line per decision and why, newest last.
---

# Decisions

- 2026-10-06: Bundle the pinned scrcpy-server 5.0 from Homebrew, checked against its SHA-256 in `scripts/build-app.sh`. The server's stream protocol has to match the version the app parses.
- 2026-10-06: Send frames with native CoreMediaIO into the OBS extension's sink stream. No Python runtime (pyvirtualcam), no OBS scene and no scrcpy window in the path.
- 2026-10-06: No silent resolution fallback. The app passes `downsize_on_error=false` and stops when the session size differs from the chosen mode, so the output is never quietly smaller than asked.
- 2026-10-06: Require hardware HEVC decoding, so 4K60 decoding doesn't fall back to the CPU.
- 2026-10-06: The app cleans up only what it created: its temporary server path on the phone, its forward entry and its child. It never stops the shared ADB server.
- 2026-10-06: The build uses the Xcode beta toolchain only for its own child commands, through `DEVELOPER_DIR`, and doesn't change the Mac's selected toolchain.
- 2026-10-19: Project history lives in kata (bugs, requests) and this folder (what's true now).
- 2026-10-19: USB only (Harsha's call). The app keeps hiding ADB devices that have no `usb:` field, so a phone on wireless ADB has to be plugged in; Wi-Fi may not keep up with 40 Mbps 4K60 HEVC. kata:android-webcam#0hz3
- 2026-10-19: Keep the OBS camera extension as it is (Harsha's call). The app keeps sending NV12 at the mode's size even though OBS advertises 1920x1080 BGRA; the first phone test, kata:android-webcam#hbt7, checks whether receivers accept it. kata:android-webcam#t190
- 2026-10-19: Download the pinned scrcpy-server 5.0.1 from its GitHub release and check its SHA-256, instead of copying it from Homebrew, which moved on to 5.0.1 and broke the build. This replaces the 2026-10-06 Homebrew line. kata:android-webcam#mm61
- 2026-10-19: Use the selected Xcode (or `DEVELOPER_DIR` when set) for builds, so strangers can build without the Xcode beta. This replaces the 2026-10-06 Xcode beta line.
- 2026-10-19: Find `adb` in `$ADB`, `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, then Homebrew paths, and give every adb call a time limit. kata:android-webcam#bq44
- 2026-10-19: Reconnect only after a session has sent a frame and only for transport errors (adb, socket). Setup errors stop capture with their message, so a mode the phone can't run doesn't loop. kata:android-webcam#gb7k
- 2026-10-19: When OBS opens during capture, warn and keep capturing, so a call isn't cut off. kata:android-webcam#1b4s
- 2026-10-19: Start in 1080p at 30 fps, which keeps the phone cooler than 4K60, and remember the last phone and mode. kata:android-webcam#xzjd
- 2026-10-19: Menu layout C, a native menu with a live header (Harsha's pick from `design/mockups/index.html` in the sandbox). Image controls live in their own window because sliders don't fit in menus.
- 2026-10-19: Apache-2.0 license (Harsha's call), matching the bundled scrcpy server. kata:android-webcam#w5gj
- 2026-10-19: Launch at login is a setting, off by default (Harsha's call), through `SMAppService.mainApp`.
- 2026-10-19: Ship our own build of scrcpy-server 5.0.1 (Harsha's call): `server/webcam.patch` adds exposure, white balance, focus lock, noise reduction and edge options plus control message type 100, built from source by `scripts/build-server.sh`. This replaces the 5.0.1 download line. kata:android-webcam#wpc4
- 2026-10-20: The app has two motions, a 0.2 s ease-out fade between picture states and a slow pulse on the live badge dot and the waiting status dot. Both turn off under Reduce Motion. kata:android-webcam#jfgj
- 2026-10-20: The menu bar icon has three looks: `camera` when off, `camera.fill` when live, `camera.badge.ellipsis` while starting, switching lens, reconnecting or stopping. A hot phone stays in the menu and its notification, since SF Symbols has no camera-with-warning badge. kata:android-webcam#be95
- 2026-10-20: The preview window keeps 16:9, since every capture mode is 16:9, and remembers its size and place. kata:android-webcam#kehx
- 2026-10-20: App windows come forward with `orderFrontRegardless()` after activation, because activation alone leaves an accessory app's window behind the app in front. The app also installs a hidden main menu so Command-W, Command-C and Command-Q work in its windows. kata:android-webcam#xhjr kata:android-webcam#b3ts
