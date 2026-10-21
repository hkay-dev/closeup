---
type: log
summary: The sprint got the app ready for the wireless latency test, then grew into a bug bash, two fixes it found and new ways for agents to walk the app without a phone or your screen.
project: android-webcam
sprint: android-webcam-wireless-adb-latency-check
window: 2026-10-21T13:08:15Z/2026-10-21T17:11:06Z
tickets: [android-webcam#wnmp, android-webcam#s902, android-webcam#rcbj, android-webcam#fknj, android-webcam#yt4m, android-webcam#2a6e, android-webcam#zhvc]
---

# Android Webcam: wireless ADB latency check

The sprint got the app ready for the wireless latency test, then grew into a bug bash, two fixes it found and new ways for agents to walk the app without a phone or your screen. Every ticket landed on main; nothing here was tried on your phone yet.

## Patch notes

- New: A hidden switch lets a phone on wireless debugging through, shows it once even with the cable in, and logs one line a second of frames, gaps and lag while it runs. It's set up for your latency session against the 50 ms bar, not tried on your phone yet (android-webcam#wnmp, d531cd4)
- Fixed: The menu header no longer keeps saying "OBS opened" after you quit OBS, live or stopped. Not tried on screen yet (android-webcam#fknj, 930617c)
- Fixed: Setup no longer sticks on "OBS camera extension" after you approve it. macOS doesn't show a newly approved camera to an app that's already running, so the app now reopens itself once. Not driven end to end yet (android-webcam#yt4m, 756539c)
- Fixed: The app builds again with the Command Line Tools toolchain, not only with the Xcode beta (android-webcam#rcbj, cdb3e7d)
- Under the hood: A bug bash walked the app in a VM against an emulator standing in for the phone, wrote a map of your journeys and filed the two bugs fixed above (android-webcam#s902, b728c4d)
- Under the hood: Agents can now run an off-screen copy of the app from a terminal, read its menu and windows, press its buttons and take screenshots, with its own settings and nothing on your screen (android-webcam#2a6e, aa3ea01)
- Under the hood: A macOS VM base with OBS and its camera extension already approved saves each walk about 8 minutes (android-webcam#zhvc, 57dbc5e)

## Waits on you

- android-webcam#wnmp, Test it: the wireless latency session with your phone, USB first and then wireless, steps are on the ticket. Phone sessions start when you say go
- android-webcam#fknj, Test it: open and quit OBS while the webcam is live and stopped, the note should go away
- android-webcam#yt4m, Test it: on a Mac where OBS's camera extension isn't approved yet, approve it and watch the app reopen once with the step done

## Where it landed

- android-webcam#wnmp Test the webcam over wireless ADB against the 50 ms bar: Done, in the dev build, the measuring is still yours (d531cd4)
- android-webcam#s902 Bug bash: use Android Webcam the way Harsha does and file what breaks: Done, 2 filed, 3 set aside (b728c4d)
- android-webcam#rcbj Build fails with the Command Line Tools toolchain in Settings' launch at login toggle: Done, in the dev build (cdb3e7d)
- android-webcam#fknj Header keeps saying OBS opened after OBS is closed: Done, in the dev build, not tried on screen (930617c)
- android-webcam#yt4m Setup says the OBS camera extension is off after I approved it, until I relaunch the app: Done, in the dev build, not driven end to end (756539c)
- android-webcam#2a6e Setup: off-screen dev automation to drive the Mac journeys without a VM: Done, in the dev build (aa3ea01)
- android-webcam#zhvc Setup: a macOS VM base with OBS approved for webcam walks: Done (57dbc5e)

## Calls

- The wireless switch is a hidden defaults key wirelessAdb plus an ANDROID_WEBCAM_WIRELESS env override, read once per launch, not a Settings item (android-webcam#wnmp)
- When one phone shows over USB and wireless, the wireless entry wins for the whole session, rather than falling back to the cable on a Wi-Fi drop (android-webcam#wnmp)
- Phones are matched across USB and wireless by the hardware serial in the mDNS name (ip:port entries by product, model and device only when one fits), rather than listing both (android-webcam#wnmp)
- behind_ms in the per-second log is arrival minus pts relative to the least delayed packet so far, rather than the raw clock difference between phone and Mac (android-webcam#wnmp)
- --diagnose lists wireless phones under wireless_devices even with the switch off, rather than hiding them (android-webcam#wnmp)
- The bug bash files bugs and doesn't fix them itself, against the charter's "fix the S ones in this ticket"; the filed bugs ran as their own tickets (android-webcam#s902)
- Replaced SwiftUI @State in the Setup and Settings windows with a small observable box (Command Line Tools has no SwiftUI macro plugin), rather than requiring full Xcode to build (android-webcam#rcbj)
- Check Audio Sync with a microphone is left for your real mic session instead of turning on a VM microphone (android-webcam#s902)
- The app reopens itself once when the OBS extension is approved but the running copy can't see it, rather than a Setup line telling you to reopen it or running the camera in a helper process (android-webcam#yt4m)
- The bug bash's ask for a VM base with OBS approved went in as a ticket instead of a Decide, since it's tooling (android-webcam#s902)
- The dev switch is the env var ANDROID_WEBCAM_DEV_DIR, rather than a command-line flag next to --diagnose (android-webcam#2a6e)
- The dev copy of the app has no menu bar icon at all, rather than a hidden one (hiding it would be saved in your real settings) (android-webcam#2a6e)
- The dev window walk uses the app's own accessibility tree, rather than System Events, so it needs no Accessibility permission (android-webcam#2a6e)

## Set aside

- android-webcam#s902: Not driven: a "camera in use" error (the emulator can't produce it), Mac sleep (needs a real Mac), Check Audio Sync with a mic, notification banner clicks, and some Where features meet pairs (second phone, start when plugged in, adb gone mid-capture, wireless against USB). The off-screen dev copy (android-webcam#2a6e) and the OBS base (android-webcam#zhvc) make the next bash cheaper.
- android-webcam#s902: Below the bar, not filed: with an offline phone the menu says "allow USB debugging on the phone", which is misleading.
- android-webcam#2a6e: The dev copy can't start the webcam past Setup without a phone; a fake adb for it wasn't built.
