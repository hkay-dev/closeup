# Android Webcam

Use your Android phone's camera as your Mac's webcam, over a USB cable. There's no app to install on the phone, no account and no cloud: the Mac talks to the phone's camera directly and hands the picture to any call or recording app.

It has run live with a Galaxy S25 Ultra into a video call and a QuickTime recording. Most menu, setup, error and reconnect paths have also been driven against an Android emulator; [docs/phone-session.md](docs/phone-session.md) lists what still needs a real phone.

## What you need

- A Mac on macOS 13 or later.
- An Android phone on Android 12 or later, and a USB cable that carries data (some charging cables don't).
- About 10 minutes the first time. Setup downloads the two free tools it needs for you:
  - **Android platform tools** from Google, which the Mac uses to talk to the phone (`adb`).
  - **OBS Studio**, for its virtual camera. OBS only has to be installed; it stays closed while you use the webcam.

## Get the app

There's no signed download yet, so build it yourself (see [Build](#build)) or take the zipped app from a CI run or release. The app isn't notarized, so the first time you open it macOS refuses: open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.

## First run

The app lives in the menu bar (a camera icon). The first time it opens, the setup window walks you through six steps, each with a button that does the work:

1. **Get Android platform tools.** Click **Download Platform Tools**. It goes into the app's own folder in Application Support, nothing system-wide.
2. **Install OBS Studio.** Click **Download OBS**. The app gets the latest release from OBS's GitHub page, checks that the OBS Project signed it, and puts it in Applications. If you already have OBS, this step is done.
3. **Turn on OBS's camera.** Click **Open OBS**, then **Start Virtual Camera** in OBS. macOS asks you to allow OBS's camera extension: click **Open System Settings** and turn on OBS. Quit OBS. You only do this once.
4. **Plug in your phone** with the USB cable.
5. **Allow USB debugging.** The phone asks whether to allow this Mac; tap **Allow**. If it doesn't ask, turn on Developer options first: **Show me how** in Setup lists the taps.
6. **Close OBS Studio.** The app and OBS can't both feed the camera.

Then click **Start Webcam**. In Zoom, Meet, FaceTime, Teams or QuickTime, choose **OBS Virtual Camera** as the camera.

## Using it

- **Start Webcam** and **Stop Webcam** are at the top of the menu. The header shows the live picture, how long it's been live, and the phone's temperature and battery.
- **Capture Mode** picks 1080p at 30 fps (the default, and the coolest for the phone), 1080p at 60, 4K at 60, or an experimental 1080p at 120. Phones differ; if one can't run a mode, the app says so instead of quietly picking another.
- **Live Controls** opens a small floating panel that stays above your call without taking its keyboard focus: switch lenses, zoom (hold to keep zooming), turn on the flashlight, and set exposure, white balance, focus and sharpening while you're live. When the webcam is off it has a Start Webcam button. Settings stay for the next call. Esc closes it.
- **Show Preview** opens a picture-only window, separate from what call apps see.
- **Check Audio Sync** times a clap to measure how far the video lags the sound, so you can set an audio delay in your call or recording app.
- **Settings** has Launch at login, Start when the phone is plugged in, and notifications.

If the cable comes loose mid-call, the call keeps its camera and the picture comes back on its own when you plug the phone back in. If the phone runs hot, a notification offers to switch to 1080p at 30 fps.

### Why call apps say "OBS Virtual Camera"

The app sends its picture through OBS's camera, and OBS decides the name call apps show. A camera of the app's own, named after your phone, needs a camera extension signed with a paid Apple Developer ID, which this project doesn't have yet.

## When something's wrong

The menu says what happened and what to do next. The common ones:

| You see | Try |
| --- | --- |
| The phone isn't listed | Use a data cable, unlock the phone and tap Allow on the USB debugging prompt. If it says "connecting", unplug and plug it back in. |
| "Another app on the phone is using the camera" | Close the phone's camera app or any video call on the phone, then start again. |
| "The phone's camera can't …" this mode | Pick a lower Capture Mode. |
| Call apps don't list OBS Virtual Camera | Finish step 3 of Setup, then quit and reopen the call app. |
| The picture lags the sound | Run Check Audio Sync and set that delay on the audio in your app. |

## Privacy

The app sends video only. It doesn't record, capture your screen or send anything to the Internet; the only downloads are the two setup tools you click. It opens the microphone only while **Check Audio Sync** runs, to time a clap, and keeps nothing. It adds a login item only if you turn on **Launch at login**.

## Build

You need Xcode or the Swift toolchain. The script uses the selected Xcode; set `DEVELOPER_DIR` to use another. It builds the phone server with `scripts/build-server.sh`, which needs a JDK and the Android SDK with platform 36 and build-tools 36.0.0 (see `server/README.md`). Set `SCRCPY_SERVER_PATH` to bundle another server jar instead; its version must be `5.0.1-webcam.1`.

```sh
./scripts/build-app.sh
```

The app is written to `build/Android Webcam.app` and signed locally with an ad-hoc signature. CI builds it on every push and publishes a zip on `v*` tags.

## How it works

ADB starts this project's build of scrcpy-server 5.0.1 on the phone. A local ADB forwarding socket carries framed HEVC packets, and a second socket carries camera controls. VideoToolbox decodes the video to NV12 pixel buffers, an optional Core Image step sharpens them, and CoreMediaIO sends them directly to the OBS extension's sink stream. The preview shows the same frames, and its size never changes what call apps get. There's no scrcpy desktop window or OBS scene in this path.

The app learns about phones from one long-running `adb track-devices -l` client, which reports each plug-in, unplug and USB debugging approval as it happens. While the webcam runs, the app holds an activity assertion that keeps App Nap from slowing the frame path; it doesn't stop the Mac from sleeping.

The app owns its temporary server file, forwarding entry and child process. Stop and Quit clean up only those, and the next launch removes what a killed session left. It never stops the shared ADB server.

The app looks for `adb` in `$ADB`, `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, the copy Setup downloads (`~/Library/Application Support/Android Webcam/platform-tools`), `/opt/homebrew/bin` and `/usr/local/bin`.

### Modes

- 4K at 60 fps, HEVC at 40 Mbps.
- 1080p at 60 fps, HEVC at 20 Mbps.
- 1080p at 30 fps, HEVC at 12 Mbps.
- 1080p at 120 fps, experimental high-speed capture at 40 Mbps.

The requested size is checked against the server's session metadata. The stock OBS extension advertises 1080p60 even when it gets 4K buffers, and this app inherits that.

### Headless checks

These don't create the menu bar item, open a window, start the phone's camera or publish to the virtual camera.

```sh
'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --diagnose
'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --probe-hevc path/to/sample.hevc
```

`--diagnose` checks USB device discovery, the bundled server and the OBS extension's device identity. It also reports the hidden wireless switch (see [docs/wireless-latency-session.md](docs/wireless-latency-session.md)). `--probe-hevc` checks the hardware decoder with an Annex B HEVC sample.

To walk the menu and every window without a VM and without anything showing on screen, run the app as an off-screen dev instance with `scripts/dev.sh`, and stand in for a phone with an emulator and `scripts/fault-adb`. See [docs/dev-automation.md](docs/dev-automation.md).

## Dependencies and references

The bundled server is [scrcpy](https://github.com/Genymobile/scrcpy/tree/v5.0.1) 5.0.1, Apache-2.0 software from Genymobile, built from source with this project's patch in `server/webcam.patch`. Its license is included in the app's resources. Its [5.0.1 server protocol](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java) is unchanged apart from the additions in `server/README.md`.

The [pyvirtualcam macOS backend](https://github.com/letmaik/pyvirtualcam/tree/main/pyvirtualcam/native_macos_obs_cmioextension) documents the OBS sink-stream route. This app uses native CoreMediaIO APIs and doesn't include a Python runtime.

Android Webcam is licensed under Apache-2.0 (see `LICENSE` and `NOTICE`).
