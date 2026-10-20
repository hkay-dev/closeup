# Phone server

The app ships its own build of [scrcpy](https://github.com/Genymobile/scrcpy) server v5.0.1 (commit `a60891aea193d92e7e5c3942700eca63f9d19a5f`) with `webcam.patch` applied. Without the new options and message below, the server behaves like stock 5.0.1. Its version name is `5.0.1-webcam.1`, so the app must pass that as the first server argument.

## What the patch adds

Server options, all optional. Unset means the camera's automatic behavior.

| Option | Values | Camera2 key |
| --- | --- | --- |
| `webcam_exposure` | float, in EV | `CONTROL_AE_EXPOSURE_COMPENSATION`, converted with `CONTROL_AE_COMPENSATION_STEP` and clamped to `CONTROL_AE_COMPENSATION_RANGE` |
| `webcam_awb` | `auto`, `daylight`, `cloudy`, `incandescent`, `fluorescent` | `CONTROL_AWB_MODE` |
| `webcam_focus` | `continuous`, `locked` | `CONTROL_AF_MODE` |
| `webcam_nr` | `off`, `fast`, `high_quality` | `NOISE_REDUCTION_MODE` |
| `webcam_edge` | `off`, `fast`, `high_quality` | `EDGE_MODE` (phone-side sharpening) |

`locked` focus keeps `CONTROL_AF_MODE_CONTINUOUS_VIDEO` and sends one `CONTROL_AF_TRIGGER_START` once the continuous search has settled (`PASSIVE_FOCUSED` or `PASSIVE_UNFOCUSED`, or after 90 frames), which holds the lens where it is. Going back to `continuous` sends `CONTROL_AF_TRIGGER_CANCEL`.

A value the camera doesn't list as available goes back to the `TEMPLATE_RECORD` default and logs a warning; the session keeps running. An unknown option name or value fails at startup, like other scrcpy options.

`list_cameras=true` appends `, focal=<mm>` (the smallest `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`, 2 decimals) before each camera line's closing `)`:

```
    --camera-id=0    (back, 4080x3060, fps={15, 24, 30, 60}, zoom-range=[0.6, 10.0], focal=6.30)
```

## Control message

Type `100`, sent on the control socket in camera mode, big-endian, 9 bytes:

```
[u8 type=100][i32 exposure_ev_times_100][u8 awb][u8 focus][u8 nr][u8 edge]
```

Indexes follow the option values above: awb `0 auto, 1 daylight, 2 cloudy, 3 incandescent, 4 fluorescent`; focus `0 continuous, 1 locked`; nr and edge `0 off, 1 fast, 2 high_quality`. Every field is applied, and an out-of-range index counts as unsupported. The server updates the running repeating request without restarting the camera, and keeps the values for later sessions of the same server (for example after a rotation reset).

Stock camera messages still work: `18` torch (`[u8 18][u8 on]`), `19` zoom in, `20` zoom out.

## Rebuilding

```sh
scripts/build-server.sh
```

It clones tag v5.0.1 into `build/cache/scrcpy-src` if it's missing and checks the commit, exports a clean copy to `build/cache/scrcpy-webcam`, applies the patch, sets the version name, and runs scrcpy's own `server/build_without_gradle.sh`. The result is `build/scrcpy-server-webcam.jar`. It's skipped when that file is newer than the patch and the script.

It needs `ANDROID_HOME` (default `~/Library/Android/sdk`) with platform 36 and build-tools 36.0.0, and a JDK: `JAVA_HOME`, else Android Studio's bundled JBR, else Homebrew's `openjdk@17`.

To change the patch, edit a clone of v5.0.1, then write it with `git add -N <new files> && git diff v5.0.1 > server/webcam.patch`.

## License

scrcpy is Copyright (C) 2018 Genymobile and Copyright (C) 2018-2026 Romain Vimont, licensed under the Apache License, Version 2.0 (see `Resources/scrcpy-LICENSE.txt`). `webcam.patch` modifies its server source files, and the built jar is a modified version of the scrcpy server. The patch is distributed under the same license.
