<p align="center">
  <img src="docs/assets/brand/header.png" alt="Closeup" width="800">
</p>

<p align="center">
  <strong>Use your Android phone's camera as your Mac's webcam, over USB or Wi-Fi.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-blue" alt="Apple silicon and Intel">
  <img src="https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white" alt="Android 12 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-green" alt="License: Apache-2.0"></a>
</p>

Closeup is a small menu bar app for the Mac. Plug in your phone, click **Start Webcam**, and pick **OBS Virtual Camera** in Zoom, Meet, FaceTime, Teams or QuickTime. There's no app to install on the phone, no account and no cloud: the Mac talks to the phone's camera directly and hands the picture to any call or recording app.

It has run live with a Galaxy S25 Ultra into a video call and a QuickTime recording. Most menu, setup, error and reconnect paths have also been driven against an Android emulator; [docs/phone-session.md](docs/phone-session.md) lists what still needs a real phone.

<p align="center">
  <img src="docs/assets/live-controls.png" width="300" alt="Live Controls: lens chips, zoom, flashlight, exposure, white balance, focus and sharpening">
  &nbsp;
  <img src="docs/assets/setup.png" width="440" alt="Setup walks you through five steps and can do the Mac's part for you">
</p>

## Contents

- [What it does](#what-it-does)
- [How it works](#how-it-works)
- [What you need](#what-you-need)
- [Install](#install)
- [First run](#first-run)
- [Using it](#using-it)
- [Wi-Fi](#wi-fi)
- [When something's wrong](#when-somethings-wrong)
- [Privacy](#privacy)
- [Where files go](#where-files-go)
- [Uninstall](#uninstall)
- [Build](#build)
- [Credits](#credits)
- [License](#license)

## What it does

- **Lives in the menu bar.** The menu's header shows the phone's name and status, how it's connected (USB or Wi-Fi), its temperature and battery, and the live picture. The menu bar icon turns red with the call's clock while you're live.
- **Picks the picture you want.** 1080p at 30 or 60 fps, 4K at 60, or an experimental 1080p at 120. Landscape, Portrait or Auto-Rotate, and it never comes out upside down.
- **Live Controls.** A small floating panel for lenses, zoom, flashlight, exposure, white balance, focus and sharpening, that you can open from any app with ⌃⌥⌘L.
- **Check Audio Sync.** Clap once and it tells you how far the video is behind the sound.
- **Sets itself up.** Setup downloads Google's platform tools and OBS Studio and turns on OBS's camera for you.
- **Works over Wi-Fi too.** Pair the phone once with a QR code and it connects by itself after that.
- **Keeps going.** If the cable comes loose mid-call, the call keeps its camera and the picture comes back when you plug the phone in again.

## How it works

```mermaid
flowchart LR
    phone["Phone camera"] --> server["Patched scrcpy server<br/>on the phone"]
    server -- "adb over USB or Wi-Fi" --> closeup["Closeup<br/>on the Mac"]
    closeup --> obs["OBS Virtual Camera"]
    obs --> apps["Zoom, Meet, FaceTime,<br/>Teams, QuickTime"]
```

Closeup starts its own build of the [scrcpy](https://github.com/Genymobile/scrcpy) server on the phone over adb, gets the camera's video back as HEVC, decodes it in hardware on the Mac and writes the frames straight into OBS's virtual camera. OBS has to be installed for its camera, but it stays closed. There's no scrcpy window and no OBS scene in the path. [More detail below](#under-the-hood).

## What you need

- A Mac on macOS 13 or later. Release builds run on Apple silicon and Intel Macs; only Apple silicon has been tried.
- An Android phone on Android 12 or later, and a USB cable that carries data (some charging cables don't).
- About 10 minutes the first time. Setup downloads the two free tools it needs for you:
  - **Android platform tools** from Google, which the Mac uses to talk to the phone (`adb`).
  - **OBS Studio**, for its virtual camera. OBS only has to be installed; it stays closed while you use the webcam.

### Phones

Any phone on Android 12 or later with a back or front camera that Android's Camera2 API can open; the app checks the version and says so on older ones. Capture modes and lenses depend on the phone: a mode it can't run shows an error, and Live Controls lists the lenses the phone reports. It has been tried live on a Galaxy S25 Ultra only, so reports from other phones help.

## Install

There's no signed download yet. Download `Closeup.dmg` from the [releases page](https://github.com/hkay-dev/closeup/releases), or build it yourself (see [Build](#build)). Open the disk image, drag **Closeup** onto the **Applications** folder next to it, then eject the disk image. Open the app from Applications, not from the disk image or Downloads.

The app is ad-hoc signed and not notarized, so macOS blocks the first open:

1. Double-click the app. macOS says "“Closeup” Not Opened"; click **Done**.
2. Open **System Settings › Privacy & Security** (scroll down the sidebar to find it), then scroll to the bottom of the page. Next to "“Closeup” was blocked to protect your Mac", click **Open Anyway**. The button shows for about an hour after step 1.
3. In the "Open “Closeup”?" dialog, click **Open Anyway**. The password box takes a few seconds to appear; enter your password. The app opens and Setup appears.

Each new version is a new unsigned build, so you do this again after an update.

## First run

The app lives in the menu bar (a camera icon). The first time it opens, the Setup window walks you through five steps. While Setup is open the app also has a Dock icon (it bounces when Setup is waiting behind another window), so you can get back to it from behind System Settings. When you close Setup the Dock icon goes, and macOS may say once that "Closeup" is running in the background: that's the menu bar app, as intended.

Click **Set Up for Me** and the app does steps 1 to 3 by itself, except for one approval that macOS asks you for. You can set up the phone while it downloads. Each step also has its own button if you'd rather go one at a time.

1. **Get Android platform tools.** Google's adb, which talks to the phone. It goes into the app's own folder in Application Support, nothing system-wide. The app turns off adb's wireless phone search, so macOS shouldn't ask about local networks; if it does (another tool started adb first), **Don't Allow** is fine, USB doesn't need it.
2. **Install OBS Studio.** The app gets the latest release from OBS's GitHub page (about 150 MB), checks that the OBS Project signed it, and puts it in Applications. If you already have OBS, this step is done.
3. **Turn on OBS's camera.** The app starts OBS in the background (on a Mac where OBS has never run, it first sets OBS to skip its welcome windows). macOS asks about a new camera extension from OBS: click **Open System Settings**, click the switch next to OBS and type your password. If you closed that box, **Open Camera Extensions** in Setup gets you to the same switch. The app then quits OBS, reopens itself once, and moves on.
4. **Connect your phone.** Setup watches the USB port and shows what to do next, with a little phone acting out the taps:
   - Plug the phone in with a cable that carries data, not just power.
   - Turn on Developer options: in **Settings › About phone** (on Samsung, then **Software information**), tap **Build number** 7 times and enter your PIN. This unlocks settings for app developers; the webcam needs one of them, USB debugging, to read the camera directly.
   - In **Settings › Developer options** (on Samsung, at the bottom of Settings; on a Pixel, in **System**), turn on **USB debugging**.
   - The phone asks "Allow USB debugging?": tick **Always allow from this computer** and tap **Allow**.
5. **Close OBS Studio.** The app and OBS can't both feed the camera. OBS can stay installed.

Then click **Start Webcam**. In Zoom, Meet, FaceTime, Teams or QuickTime, choose **OBS Virtual Camera** as the camera.

## Using it

- **Start Webcam** and **Stop Webcam** are at the top of the menu once a phone is ready; until then that spot says **Finish Setup…** and the next step.
- **The header** shows the phone's name next to its status, how it's connected (USB or Wi-Fi), its temperature and battery, and the live picture. A warm phone or a low battery changes color; hover over it to see why. With no phone on USB or Wi-Fi, the picture is a gray screen and the readings are dashes.
- **Phone, Capture Mode, Orientation and Camera** each show what's picked. Start, Stop and the choices in the submenus leave the menu open, so you see the picture come up or the check mark move; click the icon again or anywhere else to close it.
- **The menu bar icon** turns red with the call's clock while you're live.
- **Capture Mode** picks 1080p at 30 fps (the default, and the coolest for the phone), 1080p at 60, 4K at 60, or an experimental 1080p at 120. Phones differ; if one can't run a mode, the app says so instead of quietly picking another.
- **Orientation** sets how you hold the phone. **Landscape** (the default) is sideways, and **Portrait** is upright, with the tall picture between black bars, since call apps always get a wide picture. Either way round works: the phone's motion sensor tells the app which way is up, so the picture never comes out upside down. **Auto-Rotate** follows the phone through all four turns, for walking around with it in your hand. It changes the live picture at once, from the menu or Live Controls. If Landscape is picked and you hold the phone upright, the menu and Live Controls mention it.
- **Live Controls** (⌃⌥⌘L from any app) opens a small floating panel that stays above your call and never takes its keyboard, so mute and push-to-talk keep working: switch lenses, zoom (hold to keep zooming), turn on the flashlight, pick the orientation, and set exposure, white balance, focus and sharpening while you're live. When the webcam is off it has a Start Webcam button. Settings stay for the next call.
- **Show Preview** opens a picture-only window, separate from what call apps see.
- **Check Audio Sync** times a clap to measure how far the video lags the sound, so you can set an audio delay in your call or recording app.
- **Settings** has Launch at login, Start when the phone is plugged in, notifications, Phones over Wi-Fi and the Live Controls shortcut. Its Help section has **Copy Diagnostics**, which copies a plain-text report (versions, Mac, adb, OBS, the phone's model, setup steps and recent errors, with serial numbers taken out) to paste into a bug report, **Run Setup Again**, and **Check for Updates**, which asks GitHub for the newest release and links to it.

<p align="center">
  <img src="docs/assets/settings.png" width="480" alt="Settings, with General, Phone, Live Controls and Help in a sidebar">
  &nbsp;
  <img src="docs/assets/audio-sync.png" width="420" alt="Check Audio Sync: clap once and it says how far the video is behind the sound">
</p>

If the cable comes loose mid-call, the call keeps its camera and the picture comes back on its own when you plug the phone back in. If the phone runs hot, a notification offers to switch to 1080p at 30 fps.

### Why call apps say "OBS Virtual Camera"

While you're live, the menu says which camera to pick, and its **Why is it called that?** link explains this too.

The app sends its picture through OBS's camera, and OBS decides the name that call apps show. A camera of the app's own, named after your phone, needs a camera extension signed with a paid Apple Developer ID, which this project doesn't have yet.

## Wi-Fi

A cable keeps the phone charged and gives the steadiest picture, but you can also go without one:

1. In the menu, choose **Phone › Connect a Phone over Wi-Fi…**. A window with a QR code opens.
2. On the phone, open **Developer options › Wireless debugging** and tap **Pair device with QR code**, then point it at the window. You can also type the phone's six-digit pairing code into the window instead.
3. The window says when the phone is connected.

You only pair once. After that the phone connects by itself whenever it's on the same Wi-Fi, and the Phone menu shows a Wi-Fi or cable symbol next to each phone. **Settings › Phones over Wi-Fi** turns it off again. On the author's home network, 4K at 60 still ran at 59 fps over Wi-Fi.

## When something's wrong

The menu says what happened and what to do next. The common ones:

| You see | Try |
| --- | --- |
| The phone isn't listed | Use a data cable, unlock the phone and tap Allow on the USB debugging prompt. If it says "connecting", unplug and plug it back in. |
| "Another app on the phone is using the camera" | Close the phone's camera app or any video call on the phone, then start again. |
| "The phone's camera can't …" this mode | Pick a lower Capture Mode. |
| Call apps don't list OBS Virtual Camera | Finish step 3 of Setup, then quit and reopen the call app. |
| The picture lags the sound | Run Check Audio Sync and set that delay on the audio in your app. |

### Report a problem

Open an issue at [github.com/hkay-dev/closeup/issues](https://github.com/hkay-dev/closeup/issues); the bug form asks for the phone and the diagnostics. In **Settings › Help**, click **Copy Diagnostics** and paste the report into the issue. It has the versions, the phone's model, the setup steps and recent errors, with serial numbers taken out.

<details>
<summary><strong>Headless checks and logs</strong></summary>

These don't create the menu bar item, open a window, start the phone's camera or publish to the virtual camera.

```sh
build/Closeup.app/Contents/MacOS/Closeup --diagnose
build/Closeup.app/Contents/MacOS/Closeup --probe-hevc path/to/sample.hevc
```

`--diagnose` checks USB device discovery, the bundled server and the OBS extension's device identity. It also reports the Phones over Wi-Fi switch (see [docs/wireless-latency-session.md](docs/wireless-latency-session.md)). `--probe-hevc` checks the hardware decoder with an Annex B HEVC sample. For an installed copy, use `/Applications/Closeup.app/Contents/MacOS/Closeup` instead.

The app logs under the subsystem `com.harsha.closeup`:

```sh
log stream --level info --predicate 'subsystem == "com.harsha.closeup"'
```

</details>

## Privacy

The app sends video only. It doesn't record, capture your screen or send anything to the Internet. It only goes online for the two setup downloads you click and when you click **Check for Updates**, which asks GitHub for the newest release number. It opens the microphone only while **Check Audio Sync** runs, to time a clap, and keeps nothing. It adds a login item only if you turn on **Launch at login**.

## Where files go

- `~/Library/Application Support/Closeup/platform-tools/`: the adb that Setup downloads.
- `~/Library/Application Support/com.harsha.closeup/session.json`: what the last session started, so the next launch can clean up after a crash.
- `~/Library/Preferences/com.harsha.closeup.plist`: settings.
- `~/Library/Caches/com.harsha.closeup` and `~/Library/HTTPStorages/com.harsha.closeup`: macOS's own download cache for Setup's downloads.
- `~/.android/adbkey` and `adbkey.pub`: adb's key, which your phone trusts. adb writes these, and any other Android tool on the Mac shares them.
- `/Applications/OBS.app`, if Setup installed OBS.
- On the phone, `/data/local/tmp/closeup-*.jar` while the webcam runs; the app removes it.

## Uninstall

1. Quit the app from its menu. If you turned on **Launch at login**, turn it off in Settings first.
2. Open Terminal and stop the adb server, which keeps running after the app quits:
   `"$HOME/Library/Application Support/Closeup/platform-tools/adb" kill-server`
   If it says "cannot connect to daemon", adb wasn't running, which is fine.
3. Delete the app and its files:
   ```sh
   rm -rf /Applications/Closeup.app "$HOME/Library/Application Support/Closeup" "$HOME/Library/Application Support/com.harsha.closeup" "$HOME/Library/Caches/com.harsha.closeup" "$HOME/Library/HTTPStorages/com.harsha.closeup"
   defaults delete com.harsha.closeup
   ```
4. If you don't use OBS otherwise, drag OBS to the Trash. Finder says OBS is hosting a system extension: click **Continue** and enter your password. The camera extension is fully gone after the next restart.
5. On the phone, open **Settings › Developer options**, tap **Revoke USB debugging authorizations**, and turn off USB debugging.

## Build

You need:

- Xcode 15 or later, or its Command Line Tools (`xcode-select --install`). The script uses the selected Xcode; set `DEVELOPER_DIR` to use another.
- A JDK 17 and the Android SDK's platform 36 and build-tools 36.0.0, to build the phone server (`scripts/build-server.sh`, see [server/README.md](server/README.md)). Android Studio's SDK Manager installs both. Without Android Studio, with Homebrew:

  ```sh
  brew install openjdk@17 android-commandlinetools
  export JAVA_HOME="$(brew --prefix openjdk@17)" ANDROID_HOME="$HOME/Library/Android/sdk"
  yes | sdkmanager --sdk_root="$ANDROID_HOME" "platforms;android-36" "build-tools;36.0.0"
  ```
- Network access the first time: the script clones scrcpy v5.0.1 from GitHub.

```sh
./scripts/build-app.sh
```

That builds the phone server into `build/scrcpy-server-webcam.jar`, then writes the app to `build/Closeup.app` and signs it locally with an ad-hoc signature. Set `SCRCPY_SERVER_PATH` to bundle a server jar you already have instead of building it again; its version must be `5.0.1-webcam.1`:

```sh
SCRCPY_SERVER_PATH=build/scrcpy-server-webcam.jar ./scripts/build-app.sh
```

`UNIVERSAL=1` builds one binary for Apple silicon and Intel, and `scripts/make-dmg.sh` packs the app into `build/Closeup.dmg`. CI builds on pushes to `main` and pull requests, and a `v*` tag publishes the DMG and a zip as a GitHub release, stamped with the tag's version.

To walk the menu and every window without a VM and without anything showing on screen, run the app as an off-screen dev instance with `scripts/dev.sh`, and stand in for a phone with an emulator and `scripts/fault-adb`. See [docs/dev-automation.md](docs/dev-automation.md).

### Under the hood

adb starts this project's build of scrcpy-server 5.0.1 on the phone. A local adb forwarding socket carries framed HEVC packets, and a second socket carries camera controls one way and the phone's orientation the other. VideoToolbox decodes the video to NV12 pixel buffers, an optional Core Image step sharpens them and turns them upright, and CoreMediaIO sends them directly to the OBS extension's sink stream. The preview shows the same frames, and its size never changes what call apps get.

The app learns about phones from one long-running `adb track-devices -l` client, which reports each plug-in, unplug and USB debugging approval as it happens. While the webcam runs, the app holds an activity assertion that keeps App Nap from slowing the frame path; it doesn't stop the Mac from sleeping.

The app owns its temporary server file, forwarding entry and child process. Stop and Quit clean up only those, and the next launch removes what a killed session left. It never stops the shared adb server.

The app looks for `adb` in `$ADB`, `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, the copy Setup downloads (`~/Library/Application Support/Closeup/platform-tools`), `/opt/homebrew/bin` and `/usr/local/bin`. The three environment variables only count when you start the app from a shell (as the headless checks do); opened from Finder it uses the fixed paths.

| Mode | Video |
| --- | --- |
| 4K at 60 fps | HEVC at 40 Mbps |
| 1080p at 60 fps | HEVC at 20 Mbps |
| 1080p at 30 fps | HEVC at 12 Mbps |
| 1080p at 120 fps | Experimental high-speed capture at 40 Mbps |

The requested size is checked against the server's session metadata. The stock OBS extension advertises 1080p60 even when it gets 4K buffers, and this app inherits that.

## Credits

- [scrcpy](https://github.com/Genymobile/scrcpy/tree/v5.0.1) by Genymobile and Romain Vimont. The bundled server is scrcpy 5.0.1, Apache-2.0, built from source with this project's patch in `server/webcam.patch`. Its license is in [Resources/scrcpy-LICENSE.txt](Resources/scrcpy-LICENSE.txt) and in the app's resources, and [NOTICE](NOTICE) lists the copyright. Its [5.0.1 server protocol](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java) is unchanged apart from the additions in [server/README.md](server/README.md).
- [OBS Studio](https://obsproject.com), whose virtual camera carries the picture to call apps. Closeup doesn't bundle OBS; Setup downloads it from OBS's own GitHub releases.
- The [pyvirtualcam macOS backend](https://github.com/letmaik/pyvirtualcam/tree/main/pyvirtualcam/native_macos_obs_cmioextension) documents the OBS sink-stream route. This app uses native CoreMediaIO APIs and doesn't include a Python runtime.

## License

Closeup is licensed under Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
