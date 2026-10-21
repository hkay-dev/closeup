---
type: reference
summary: Gotchas that the code doesn't show, one section each, with the exact error words.
---

# Notes

## The OBS extension advertises 1920x1080 BGRA and passes buffers through

OBS's camera extension tells receiving apps it sends 1920x1080 BGRA at 60 fps ([OBSCameraDeviceSource.swift](https://github.com/obsproject/obs-studio/blob/master/plugins/mac-virtualcam/src/camera-extension/OBSCameraDeviceSource.swift), lines 53-56 on 2026-10-19). Its `consumeBuffer` hands whatever arrives on the sink stream straight to the source stream, with no conversion. This app sends the decoder's NV12 buffers at the capture mode's size, up to 3840x2160, so receivers see a format that differs from the one advertised. pyvirtualcam sends UYVY into the same extension. kata:android-webcam#t190 keeps it this way until the phone test, kata:android-webcam#hbt7.

## The earlier CLI experiment

Before this app, a CLI experiment received 4K60 buffers through the OBS extension, but explicit 4K and 120 fps format requests failed. The extension only advertises 1080p60, even when its producer sends 4K buffers. On 2026-10-19 this app's sender ran 4K60 from a Galaxy S25 Ultra into a video call; QuickTime recording is still tracked in kata:android-webcam#kq0x.

## Wireless ADB devices have no `usb:` field

`adb devices -l` lists a phone on wireless ADB without a `usb:` field, for example:

```
adb-R5CY11B8DHD-KmFSaA (2)._adb-tls-connect._tcp device product:pa3quew model:SM_S938U1 device:pa3q transport_id:1
```

The app skips those lines, so with only a wireless phone attached the menu says "No USB Android phone connected" and `--diagnose` prints `"usb_devices" : []`. Plug the phone in over USB (kata:android-webcam#0hz3).

A hidden switch lets wireless phones through for the latency session and logs packet timing while capturing; it is off by default and the app stays USB only. See [wireless-latency-session.md](wireless-latency-session.md) (kata:android-webcam#wnmp).

## Never stop the shared ADB server

Other tools on this Mac use the same ADB server. Stop and Quit remove only the app's own forward entry, pushed jar and child process. Don't run `adb kill-server` or `adb forward --remove-all` to clean up after the app.

## The headless checks don't touch the camera

`--diagnose` and `--probe-hevc` don't start the phone camera, publish to the virtual camera or open a preview. A clean run of both says nothing about live capture.

## Watching the OBS extension lookups

Every CoreMediaIO device lookup for the OBS extension logs one line with a running count, and so does each `systemextensionsctl list` check (it shares the counter). Count them with `log stream --level info --predicate 'subsystem == "com.harsha.android-webcam" AND category == "obs-lookup"'`. Idle with adb found, the extension active and Setup closed, expect only the launch lookup; the 3 s timer must add none (kata:android-webcam#da0t). While the extension is missing, each 3 s tick logs a lookup followed by a system extension check.

## A running process never sees an OBS extension approved after it started

CoreMediaIO builds a process's device list at its first lookup. A camera extension approved later never shows up in that process, while a fresh process (`--diagnose`) sees it within seconds. Seen in a macOS 27.0.1 VM with OBS installed and the extension not yet approved: plain re-lookups on any thread, `kCMIOHardwarePropertyDeviceForUID`, an AVFoundation discovery session (new each time and kept with KVO), a property listener on the device list, setting the DAL run loop property (`'rnlp'`) to NULL or the main loop, allowing the DAL to unload, and waiting 100 s all stayed stale for minutes after approval. `CMIOHardwareUnload` leaves the list empty for the rest of the process.

So `VirtualCamera.extensionState()` checks a miss against `systemextensionsctl list` (`[activated enabled]` for `com.obsproject.obs-studio.mac-camera-extension`), and when macOS has the extension on but this process can't see it, the app opens a fresh copy of itself and quits, once per lineage (`ANDROID_WEBCAM_RELAUNCHED`). Start Webcam needs the device in the same process, so showing the step done without relaunching would only move the failure to Start (kata:android-webcam#yt4m).
