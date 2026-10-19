---
type: log
summary: One dated line per decision and why, newest last.
---

# Decisions

- 2026-10-19: Project history lives in kata (bugs, requests) and this folder (what's true now).
- 2026-10-19: USB only (Harsha's call). The app keeps hiding ADB devices that have no `usb:` field, so a phone on wireless ADB has to be plugged in; Wi-Fi may not keep up with 40 Mbps 4K60 HEVC. kata:android-webcam#0hz3
- 2026-10-19: Keep the OBS camera extension as it is (Harsha's call). The app keeps sending NV12 at the mode's size even though OBS advertises 1920x1080 BGRA; the first phone test, kata:android-webcam#hbt7, checks whether receivers accept it. kata:android-webcam#t190
