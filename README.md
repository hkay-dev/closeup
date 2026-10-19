# Android Webcam

A local macOS menu bar app that sends Android camera frames to the installed OBS camera extension. OBS stays installed and closed during capture. The preview reads the same decoded frames independently of webcam output.

This is a development scaffold. The Android transport and camera output need a live phone check. Do not treat a successful build as live-camera verification.

## Build

This Mac has Xcode 27 beta, ADB, and scrcpy 5.0 installed. The build uses the beta toolchain only for its child commands and bundles the installed, checksum-checked scrcpy server. It does not change the selected system toolchain.

```sh
./scripts/build-app.sh
```

The app is written to `build/Android Webcam.app` and signed locally with an ad-hoc signature. It is not notarized or installed in Applications.

## Run

Open the built app. Its camera icon appears in the menu bar. Capture starts only when you choose **Start Android Webcam**.

- Connect a USB Android phone running Android 12 or later and authorize USB debugging.
- Quit OBS. Its approved camera extension remains installed.
- Pick the phone and a capture mode, then start the webcam.
- Select **OBS Virtual Camera** in the receiving app.
- Toggle **Show Preview** independently of capture.

The app captures video only. It does not record footage, open a microphone, capture the desktop, install a login job, or transmit video to an Internet service.

## Data flow

ADB starts the pinned scrcpy-server 5.0 on the selected USB phone. A local ADB forwarding socket carries framed HEVC packets. VideoToolbox decodes them to NV12 pixel buffers. CoreMediaIO sends those buffers directly to the OBS extension's sink stream. An optional preview displays the latest decoded buffer.

Preview dimensions never become camera-output dimensions. There is no scrcpy desktop window or OBS scene in this path.

The app owns its temporary server path, forwarding entry, and child process. Stop and Quit clean up only those resources. It never stops the shared ADB server.

## Modes

- 4K at 60 fps, HEVC at 40 Mbps.
- 1080p at 60 fps, HEVC at 20 Mbps.
- 1080p at 30 fps, HEVC at 12 Mbps.
- 1080p at 120 fps, experimental high-speed capture at 40 Mbps.

Device support varies. Requested capture size is checked against the server's session metadata. There is no silent resolution fallback.

The stock OBS extension advertises 1080p60 even when its producer sends 4K buffers. The previous CLI experiment received 4K60 buffers, but explicit 4K and 120 fps format requests failed. This app inherits that extension limitation. Its direct sender has not yet been checked with a phone or a receiving app.

## Headless checks

These modes do not create the menu bar item, open a preview, start the phone camera, or publish to the virtual camera.

```sh
'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --diagnose
'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --probe-hevc path/to/sample.hevc
```

`--diagnose` checks USB device discovery, bundled server presence, and the OBS extension's device identity. `--probe-hevc` checks the hardware decoder using a supplied Annex B HEVC sample with access-unit delimiters. Probe frames are discarded.

## Checks on this Mac

The release build passed with no compiler warnings. The app's local signature, property list, and build script checks passed. Diagnostics found the bundled server and approved OBS camera extension, with no phone connected.

A synthetic HEVC sample decoded all 12 frames at 3840x2160 using hardware decoding. This checks the decoder, not sustained capture performance. Unknown command arguments and malformed probe input exited with code 1.

USB camera capture, virtual-camera publishing, and preview resizing still need an interactive check with the phone. The headless checks did not start a camera sender or a preview.

The built app launched and is running. Automated menu inspection timed out, so menu actions still need a manual check.

## Dependencies and references

The local prototype uses `/opt/homebrew/bin/adb`. A distributable app would need its own dependency packaging.

The bundled [scrcpy server](https://github.com/Genymobile/scrcpy/tree/v5.0) is Apache-2.0 software from Genymobile. Its license is included in the app's resources. Its [5.0 server protocol](https://github.com/Genymobile/scrcpy/blob/v5.0/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java) is pinned to the matching server version.

The [pyvirtualcam macOS backend](https://github.com/letmaik/pyvirtualcam/tree/main/pyvirtualcam/native_macos_obs_cmioextension) documents the OBS sink-stream route. This app uses native CoreMediaIO APIs and does not include a Python runtime.
