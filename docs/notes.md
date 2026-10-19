---
type: reference
summary: Gotchas that the code doesn't show, one section each, with the exact error words.
---

# Notes

## The OBS extension advertises 1920x1080 BGRA and passes buffers through

OBS's camera extension tells receiving apps it sends 1920x1080 BGRA at 60 fps ([OBSCameraDeviceSource.swift](https://github.com/obsproject/obs-studio/blob/master/plugins/mac-virtualcam/src/camera-extension/OBSCameraDeviceSource.swift), lines 53-56 on 2026-10-19). Its `consumeBuffer` hands whatever arrives on the sink stream straight to the source stream, with no conversion. This app sends the decoder's NV12 buffers at the capture mode's size, up to 3840x2160, so receivers see a format that differs from the one advertised. pyvirtualcam sends UYVY into the same extension. kata:android-webcam#t190 keeps it this way until the phone test, kata:android-webcam#hbt7.

## The earlier CLI experiment

Before this app, a CLI experiment received 4K60 buffers through the OBS extension, but explicit 4K and 120 fps format requests failed. The extension only advertises 1080p60, even when its producer sends 4K buffers. This app has the same limit, and its own sender hasn't been checked with a phone or a receiving app yet.

## Wireless ADB devices have no `usb:` field

`adb devices -l` lists a phone on wireless ADB without a `usb:` field, for example:

```
adb-R5CY11B8DHD-KmFSaA (2)._adb-tls-connect._tcp device product:pa3quew model:SM_S938U1 device:pa3q transport_id:1
```

The app skips those lines, so with only a wireless phone attached the menu says "No USB Android phone connected" and `--diagnose` prints `"usb_devices" : []`. Plug the phone in over USB (kata:android-webcam#0hz3).

## Never stop the shared ADB server

Other tools on this Mac use the same ADB server. Stop and Quit remove only the app's own forward entry, pushed jar and child process. Don't run `adb kill-server` or `adb forward --remove-all` to clean up after the app.

## The headless checks don't touch the camera

`--diagnose` and `--probe-hevc` don't start the phone camera, publish to the virtual camera or open a preview. A clean run of both says nothing about live capture.
