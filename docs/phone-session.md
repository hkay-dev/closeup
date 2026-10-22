---
type: guide
summary: The ordered checklist for a live session with the Galaxy S25 Ultra - what only the real phone can show, the steps, what to look for, and the kata refs each one closes.
---

# Phone session

What's left after the 2026-10-22 pass (kata:android-webcam#5xnx). That pass drove the menu, setup, errors, reconnect, autostart, heat, lens fallback and cleanup against an emulator through `scripts/fault-adb` (docs/dev-automation.md), so this list keeps to what needs the real camera, real banners, a real cable or a real Mac sleep. It is the checklist of kata:android-webcam#hbt7. File each failure as its own bug.

About 90 minutes without the optional parts at the end. The order keeps the phone cool early and puts the long run where it can overlap other steps.

## Before

1. The agent takes the phone lease: `~/.agents/skills/android-dev/scripts/devlease take phone <you> --ttl 180`.
2. Plug in the S25 Ultra over USB-C and unlock it. `adb devices -l` lists it with a `usb:` field.
3. Quit any running Android Webcam. Build once: `scripts/build-app.sh`.
4. `'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --diagnose` shows the phone under `usb_devices` and `obs_camera_installed: true`.
5. Start the app from a terminal so its log is kept: `'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' 2>&1 | tee /tmp/aw-phone.log`. Settings > Notifications on.
6. In a second terminal, keep the phone's temperature in view: `watch -n 10 "adb shell dumpsys battery | grep temperature"`.

## 1. Start and the receiving apps (15 min)

| Step | Look for | Refs |
| --- | --- | --- |
| Start Webcam (1080p · 30, the default) | macOS asks for notification permission once, then "Webcam is live". Icon goes `camera.badge.ellipsis`, then `camera.fill`. | 80e0, wj6m, be95, xzjd |
| Pick OBS Virtual Camera in Chrome (Meet), then Zoom, then FaceTime | Each shows the phone's picture | hbt7 |
| Close the menu, wait 10 s, open it again | The thumbnail is current, not the last one | w31h |
| Show Preview, resize it, keep the menu open over it | Stays 16:9, keeps moving while the menu is open | qtef, hbt7 |
| Close the preview | The menu thumbnail keeps moving | |
| Choose every menu item once while live | Nothing stops the stream | hbt7 |

## 2. Modes (15 min)

Stop between modes; the mode menu is locked while live.

| Step | Look for | Refs |
| --- | --- | --- |
| 1080p · 60 | Live, smooth in the receiver | |
| 4K · 60, with the phone's camera closed for a minute first | Goes live within about 10 s | mkzk |
| QuickTime > New Movie Recording, camera OBS Virtual Camera, Maximum quality, record 20 s | It records and plays back | kq0x |
| 1080p · 120 | Live, or one plain sentence saying the camera can't do 120 fps (no loop) | |
| Back to 1080p · 30 | The decoder takes the new size without a stop | bgpr |

## 3. Lenses and picture controls (15 min)

| Step | Look for | Refs |
| --- | --- | --- |
| Camera menu: every lens, at 1080p · 30 | Each one shows; the header says "Switching camera" between | 6xxm |
| At 4K · 60, pick each lens | A lens that can't do 4K goes back to the last one with the note "X can't run 4K · 60. The webcam went back to Y." and the call keeps its picture | 6xxm, 5xnx |
| Zoom In, Zoom Out, Flashlight | The picture zooms; the torch lights and gets a tick | pz06 |
| Image Settings: exposure, white balance, focus, noise reduction, sharpness, one at a time | Each changes the picture. Write down any that do nothing; Samsung's camera may ignore some | wpc4 |
| Extra sharpening on the Mac | Edges get crisper | b4y5 |
| Switch lens, then Stop and Start | The image settings stay | wpc4 |
| Reset to Automatic | Everything goes back | |

## 4. Clap test (5 min)

Check Audio Sync, Start, one clap in the middle of the picture, three times. The meter moves, it stops about 1.6 s after the clap, and it reads "Video N ms behind". Note the three numbers. Refs zt1n, 3z0f.

## 5. Cable, camera conflicts and plug-in start (15 min)

| Step | Look for | Refs |
| --- | --- | --- |
| Pull the cable for 5 s mid-call, then plug it back | Veil "Plug the phone back in", a "Phone disconnected" banner after about 1.5 s, then the picture comes back by itself and "Phone reconnected" replaces it | gb7k |
| Click the "Phone reconnected" banner | The menu opens | zcv7 |
| While live, open the phone's own Camera app | The webcam stops with "Another app on the phone is using the camera", with no reconnect loop | 5xnx |
| Close the Camera app, Start again | Live without relaunching | |
| Settings > Start when the phone is plugged in on. Unplug, wait 6 s, plug in | It starts by itself | xw5z |
| Stop. Open and close the menu a few times | It stays stopped | 5xnx |

## 6. Heat (runs during the long call below)

| Step | Look for | Refs |
| --- | --- | --- |
| Run 1080p · 30 for 30 minutes on a call (or with Chrome's camera open) | Header shows temperature and battery; note start and end temperature | t8pc, hbt7 |
| At 1080p · 60: `adb shell dumpsys battery set temp 450` | "Phone at 113°F" banner with a Switch to 1080p · 30 button; the button restarts at 1080p · 30 without a stop banner. `adb shell dumpsys battery reset` after | zcv7, t8pc |

## 7. Sleep and wake (5 min)

With the webcam live: `pmset -g assertions` shows no sleep-preventing assertion from Android Webcam (f8bs). Apple menu > Sleep, wait 30 s, wake. The picture comes back within about 20 s with no "Phone disconnected" banner (9vqz).

## 8. Quit and cleanup (5 min)

| Step | Look for | Refs |
| --- | --- | --- |
| Quit while live | It exits; Notification Center has no Android Webcam banners left | 5xnx |
| `adb forward --list` and `adb shell ls /data/local/tmp` | Nothing from the app (`scrcpy_`, `android-webcam-`) | w6fh |
| Rebuild with `scripts/build-app.sh`, open the app, Start | Live with no new camera or OBS prompt | hbt7 |
| Start, then `kill -9` the app, then open it again | The next launch removes the old forward | w6fh |

Release the lease: `~/.agents/skills/android-dev/scripts/devlease release phone <you>`.

## Optional, longer

- The wireless latency matrix in [wireless-latency-session.md](wireless-latency-session.md), about 2 hours (kata:android-webcam#wnmp).
- The Meet microphone delay check in [wireless-latency-plan.md](wireless-latency-plan.md) step 4, which needs a second device in the room.
