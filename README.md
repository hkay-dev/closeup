# Android Webcam

A local macOS menu bar app that sends Android camera frames to the installed OBS camera extension. OBS stays installed and closed during capture. The preview reads the same decoded frames independently of webcam output.

This is a development scaffold. The Android transport and camera output need a live phone check. Do not treat a successful build as live-camera verification.

## Build

You need Xcode or the Swift toolchain, and `adb` from Android platform tools. The script uses the selected Xcode; set `DEVELOPER_DIR` to use another. It builds the phone server with `scripts/build-server.sh`, which needs a JDK and the Android SDK with platform 36 and build-tools 36.0.0 (see `server/README.md`). Set `SCRCPY_SERVER_PATH` to bundle another server jar instead; its version must be `5.0.1-webcam.1`.

```sh
./scripts/build-app.sh
```

The app is written to `build/Android Webcam.app` and signed locally with an ad-hoc signature. It is not notarized or installed in Applications.

## Run

Open the built app. Its camera icon appears in the menu bar. On first run a setup window checks for platform tools, the OBS camera extension, the phone, USB debugging and a closed OBS. Pending steps have buttons that do the step, such as copying the install command, opening OBS or Login Items & Extensions, or quitting OBS. When every step is done, the window offers **Start Webcam**. Capture starts only when you choose **Start Webcam**, or when the phone is plugged in if you turn that on in Settings. Settings shows the app and phone server versions for bug reports.

- Connect a USB Android phone running Android 12 or later and authorize USB debugging.
- Quit OBS. Its approved camera extension remains installed.
- Pick the phone and a capture mode, then start the webcam.
- Select **OBS Virtual Camera** in the receiving app.
- Toggle **Show Preview** independently of capture.

The app sends video only. It does not record footage, capture the desktop, or transmit video to an Internet service. It opens the microphone only while **Check Audio Sync** runs, to time a clap, and keeps nothing. It adds a login item only if you turn on **Launch at login** in Settings.

## Menu

The menu shows a live thumbnail, the status, and the phone's temperature and battery while capturing. Below that sit the main action (Finish Setup, Start or Stop), a cool-down shortcut when the phone runs hot, then Phone, Capture Mode and Camera (lens, zoom, flashlight) submenus. **Image Settings** sets exposure, white balance, focus, noise reduction and sharpness on the phone, plus extra sharpening on the Mac. Notifications cover start, errors, heat and a loose cable.

## Data flow

ADB starts this project's build of scrcpy-server 5.0.1 on the selected USB phone. A local ADB forwarding socket carries framed HEVC packets, and a second socket carries camera controls. VideoToolbox decodes the video to NV12 pixel buffers, an optional Core Image step sharpens them, and CoreMediaIO sends them directly to the OBS extension's sink stream. An optional preview displays the same frames.

Preview dimensions never become camera-output dimensions. There is no scrcpy desktop window or OBS scene in this path.

The app owns its temporary server path, forwarding entry, and child process. Stop and Quit clean up only those resources. If the app is killed before it can clean up, the next launch removes what that session recorded. It never stops the shared ADB server.

If the stream drops after it has started, for example when the cable comes loose, the app keeps the virtual camera open and reconnects once the phone is back. A session that fails before its first frame stops with the error instead.

## Modes

- 4K at 60 fps, HEVC at 40 Mbps.
- 1080p at 60 fps, HEVC at 20 Mbps.
- 1080p at 30 fps, HEVC at 12 Mbps.
- 1080p at 120 fps, experimental high-speed capture at 40 Mbps.

Device support varies. Requested capture size is checked against the server's session metadata. There is no silent resolution fallback.

The stock OBS extension advertises 1080p60 even when its producer sends 4K buffers. The previous CLI experiment received 4K60 buffers, but explicit 4K and 120 fps format requests failed. This app inherits that extension limitation. The app starts in 1080p at 30 fps and remembers the last phone and mode.

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

Menu items and windows open through System Events, so the menu, Setup, Settings and Image Settings have been checked on screen without the phone.

## Dependencies and references

The app needs `adb` from Android platform tools. It looks in `$ADB`, `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, `/opt/homebrew/bin` and `/usr/local/bin`. A distributable app would need its own dependency packaging.

The bundled server is [scrcpy](https://github.com/Genymobile/scrcpy/tree/v5.0.1) 5.0.1, Apache-2.0 software from Genymobile, built from source with this project's patch in `server/webcam.patch`. Its license is included in the app's resources. Its [5.0.1 server protocol](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java) is unchanged apart from the additions in `server/README.md`.

The [pyvirtualcam macOS backend](https://github.com/letmaik/pyvirtualcam/tree/main/pyvirtualcam/native_macos_obs_cmioextension) documents the OBS sink-stream route. This app uses native CoreMediaIO APIs and does not include a Python runtime.
