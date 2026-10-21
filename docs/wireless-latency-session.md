---
type: reference
summary: How to run the wireless ADB latency session - the hidden wireless switch, the per-second capture log, and the USB-vs-wireless measurement matrix with the 50 ms and 200 ms bar.
covers:
  - Sources/AndroidWebcam/Wireless.swift
  - Sources/AndroidWebcam/Capture.swift
  - Sources/AndroidWebcam/DeviceWatcher.swift
  - Sources/AndroidWebcam/App.swift
---

# Wireless latency session

The measurement for kata:android-webcam#e1f7, revisiting the USB-only call in kata:android-webcam#0hz3. Harsha approved the bar: at 1080p30, wireless adds at most 50 ms to the USB median Check Audio Sync result, and no stall over 200 ms in five minutes. Phone sessions start when Harsha says go in chat; the agent takes the phone lease first.

## Turn the switch on

The app is USB only unless the wireless switch is on. Set it before the app launches; it is read once per launch.

```sh
defaults write com.harsha.android-webcam wirelessAdb -bool true     # on, for every launch
defaults delete com.harsha.android-webcam wirelessAdb               # off again (USB only)
```

Or for one launch from a shell, which wins over the setting (`0` turns it off):

```sh
ANDROID_WEBCAM_WIRELESS=1 'build/Android Webcam.app/Contents/MacOS/AndroidWebcam'
```

With the switch on:

- Phones on wireless debugging show in the Phone menu. The app follows them through `adb track-devices -l`, so a Wi-Fi drop goes through the same reconnect path as a loose cable.
- A phone listed over both USB and wireless shows once, as the wireless entry. The app uses that entry's serial for the whole session, so a wireless drop never moves the camera onto the cable; reconnect waits for the wireless serial to come back.
- Capture writes one log line per second (below). With the switch off none of this runs.

`--diagnose` prints `wireless_switch` and `wireless_devices` (every wireless phone adb lists, used or not). A phone on both transports appears only under `wireless_devices` while the switch is on.

```sh
ANDROID_WEBCAM_WIRELESS=1 'build/Android Webcam.app/Contents/MacOS/AndroidWebcam' --diagnose
```

## Connect the phone over wireless debugging

1. On the phone: Developer options, Wireless debugging on, then Pair device with pairing code.
2. On the Mac: `adb pair <ip>:<pairing port>` and enter the code.
3. The adb server connects a paired phone by itself over mDNS, and `adb devices -l` then shows `adb-<serial>-<random> (2)._adb-tls-connect._tcp`. If it doesn't, run `adb connect <ip>:<port>` with the port on the Wireless debugging screen; the serial is then `ip:port`.

Don't run `adb kill-server`; other tools use the same server.

For the USB baseline, turn Wireless debugging off on the phone (the cable alone then lists one entry). Leaving it on would show the wireless entry instead.

## The capture log

```sh
log stream --level info --predicate 'subsystem == "com.harsha.android-webcam" AND category == "wireless-latency"' | tee wireless-<mode>-<usb|wifi>.log
```

Each capture start writes `capture started <serial> <wireless|usb> <mode>`, which also marks a reconnect. Then one line a second:

```
frames=30 bytes=181334 max_gap_ms=41 behind_ms=3 behind_max_ms=9
```

- `frames`: video packets received that second (config packets are in `bytes` only). 30 at 1080p30; fewer means drops.
- `bytes`: payload received.
- `max_gap_ms`: the longest time between two packets. A second with no packet shows how long the gap has run so far, so one stall can show on two lines in a row.
- `behind_ms`, `behind_max_ms`: the last and the largest, that second, of the packet's arrival time on the Mac minus its pts (the phone's clock), measured from the least delayed packet since capture started. Near 0 means the link keeps up; a value that keeps climbing means frames are queueing. The clocks drift a few ms over five minutes, so read the trend.

Count stalls from a saved log:

```sh
grep -o 'max_gap_ms=[0-9]*' wireless-1080p30-wifi.log | cut -d= -f2 | awk '$1>100{a++} $1>200{b++} END{print "over 100 ms:", a+0, " over 200 ms:", b+0}'
```

Adjacent lines over the limit are one stall. Reconnects are the `capture started` lines after the first.

## Write down first

Ethernet or Wi-Fi on the Mac, the Wi-Fi band (5 or 6 GHz), the access point, the distance to the phone, and whether the phone is charging (and from what). Note what else is on the network. Record the phone's temperature at the start and end of each run.

## Measurement matrix

Modes: 4K / 60 fps (40 Mbps), 1080p / 60 fps (20 Mbps), 1080p / 30 fps (12 Mbps), 1080p / 120 fps (40 Mbps, experimental). Do USB first as the baseline, then wireless, each in all four modes.

| Mode | Transport | Check Audio Sync, 5 runs (ms) | Median | Spread (min to max) | Stalls over 100 ms / over 200 ms in 5 min | Dropped frames | Reconnects | Phone temp start/end |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4K / 60 | USB | | | | | | | |
| 4K / 60 | wireless | | | | | | | |
| 1080p / 60 | USB | | | | | | | |
| 1080p / 60 | wireless | | | | | | | |
| 1080p / 30 | USB | | | | | | | |
| 1080p / 30 | wireless | | | | | | | |
| 1080p / 120 | USB | | | | | | | |
| 1080p / 120 | wireless | | | | | | | |

Per cell:

1. Pick the mode, start the webcam, and start `log stream` into a file.
2. Run Check Audio Sync five times and write each "Video N ms behind" result. Keep the median and the spread.
3. Leave it running for five minutes with the log going. Count stalls over 100 and over 200 ms, frames below the mode's fps, and `capture started` lines after the first.
4. Stop the webcam and let the phone cool before the next mode.

If the Mac is on Wi-Fi, run one more wireless 1080p / 30 pass with AirDrop and Handoff off (or `sudo ifconfig awdl0 down`, then `up` after), since AWDL channel hops may cause regular spikes [INFERENCE: not yet seen here].

## Compare with the bar

Only the 1080p / 30 pair decides it:

- Latency: wireless median minus USB median is at most 50 ms.
- Stalls: no `max_gap_ms` over 200 in the five minutes.

The other modes say how far wireless goes, and `behind_ms` climbing tells whether a miss is queueing. If 1080p / 30 misses, the next steps are cheaper video (lower bitrate, 30 fps, encoder options, 720p) in that order, judged by eye, as the plan in kata:android-webcam#e1f7 describes. Put the table in a comment on kata:android-webcam#e1f7.
