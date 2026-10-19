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
