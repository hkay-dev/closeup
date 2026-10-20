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
- 2026-10-20: Phone discovery follows `adb track-devices -l` instead of running `adb devices -l` every 3 s. The stream restarts after 1 s when it ends and backs off to 10 s while it keeps failing. The 3 s timer now only checks for platform tools and the OBS extension while one is missing or Setup is open. kata:android-webcam#3fjn kata:android-webcam#da0t
- 2026-10-20: Capture holds a `userInitiatedAllowingIdleSystemSleep` and `latencyCritical` activity so App Nap can't throttle it, but leaves idle sleep to the call or recording app, so a webcam left running doesn't keep the Mac awake. kata:android-webcam#f8bs
- 2026-10-20: Placeholder app icon, a camera lens with a red live dot on a dark tile, drawn by `scripts/make-icon.swift` into `Resources/AppIcon.icns`. It changes with the product name. kata:android-webcam#mjnh
- 2026-10-20: Notifications keep one per topic (running, cable, heat), so a newer one replaces the last, and stopping the webcam removes the ones that no longer apply. A click opens the menu, and the heat warning has a Switch to 1080p · 30 button. The permission prompt waits for the first start. kata:android-webcam#ssvj kata:android-webcam#zcv7 kata:android-webcam#80e0
- 2026-10-20: Errors carry a plain message for the menu and notifications and a detail for the log. adb's output and the phone server's ERROR lines are translated where they name a cause the user can act on (camera in use, camera access off, unplugged, USB debugging not allowed); anything else gets a general "unplug and start again" line. A session stops waiting for the phone's socket once the server has exited. kata:android-webcam#pdzp kata:android-webcam#agkf
- 2026-10-20: Notification ids are "<topic>.<uuid>", and posting first removes the topic's delivered notification. macOS treats a request that reuses a delivered id as a silent update, so a repeat "Webcam stopped" showed no banner. kata:android-webcam#ssvj
- 2026-10-20: Check Audio Sync shows the microphone that it listens to, a level meter and progress while it listens, and stops 1.6 s after it hears the clap (8 s at most) instead of always taking 6 s. The result leads with the number ("Video 132 ms behind"). The window opens even when the webcam isn't live, with a Start Webcam button, and a denied microphone gets an Open Microphone Settings button. kata:android-webcam#3z0f kata:android-webcam#c7qd kata:android-webcam#wqss
