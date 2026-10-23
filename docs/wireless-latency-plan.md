---
type: plan
summary: How to test the webcam over wireless ADB, measure the lag it adds, tune compression if it's slow, and check whether our setup adds microphone delay on calls.
status: in-progress
---

# Wireless ADB and latency test

Request: kata:android-webcam#e1f7. This revisits the USB-only call in kata:android-webcam#0hz3. Steps 1 and 2's switch and capture log are built (kata:android-webcam#wnmp, [wireless-latency-session.md](wireless-latency-session.md)); the measurements wait on a phone session.

## What's true now

- `ADB.parseDevices` (`Sources/Closeup/Capture.swift:118-125`) drops every line without a `usb:` field, so a phone on wireless debugging never shows up.
- Video already goes through `adb forward tcp:0 localabstract:scrcpy_<scid>` with `tunnel_forward=true`. Over wireless debugging the same forward runs inside adb's TLS link to the phone, so the frame path on the Mac doesn't change. Only the hop from phone to Mac does.
- The modes send HEVC at 12, 20 and 40 Mbps (`Sources/Closeup/Video.swift:46-49`).
- Check Audio Sync measures when the clap's motion reaches the Mac minus when the mic heard it. Sound reaches the mic almost at once, so this number is close to the camera's full lag up to the virtual camera. It's the ruler for every test below.
- The virtual camera stamps each frame with the Mac's clock at the moment it's sent (`Sources/Closeup/Video.swift:259-260`), not the phone's capture time.

## Step 1: let a wireless phone through

Put it behind a hidden switch (an environment variable or a `defaults` key) and keep USB only as the default until the numbers are in.

- The mDNS serial has a space in it: `adb-R5CY11B8DHD-KmFSaA (2)._adb-tls-connect._tcp`. `parseDevices` splits on whitespace, so it would read `adb-R5CY11B8DHD-KmFSaA` as the serial and `(2)._adb-tls-connect._tcp` as the status. Either parse the serial up to the status word, or connect with `adb connect <ip>:<port>` so the serial is `ip:port`.
- With the cable in, the same phone shows twice (USB and wireless) with two serials. The menu should show one phone, and the test should pick the wireless one on purpose.
- Check that `adb track-devices -l` reports wireless drops and returns, so the existing reconnect path (the one for a loose cable) handles a Wi-Fi drop.
- Error text says to unplug the phone. That only needs changing if wireless ships.

## Step 2: measure

Take the phone lease first (android-dev skill). Write down whether the Mac is on Ethernet or Wi-Fi, the Wi-Fi band (5 or 6 GHz), the access point, the distance, and whether the phone is charging.

Add one log line per second while capturing, behind the same switch: frames received, bytes, the longest gap between packets, and arrival time minus the packet's pts. pts is the phone's capture clock, so a gap that keeps growing means frames are queueing somewhere.

For USB as the baseline, then wireless, in each of the four modes:

- Run Check Audio Sync five times and keep the median and the spread.
- Run five minutes and count stalls over 100 ms, dropped frames and reconnects.
- Watch the phone's temperature, since Wi-Fi at 40 Mbps adds radio heat on top of the camera.

If the Mac is on Wi-Fi, run one pass with AirDrop and Handoff off (or `awdl0` down). AWDL makes the Mac's Wi-Fi hop channels now and then, and that shows up as regular lag spikes [INFERENCE: common on Macs, not yet seen here].

Proposed bar for "decent", for Harsha to confirm: at 1080p30, wireless adds no more than 50 ms to the USB median and has no stall over 200 ms in five minutes.

## Step 3: if it's slow, cheaper video first

Try these in order and stop at the first one that meets the bar. Harsha judges quality by eye from a still and a few seconds of motion at each setting.

1. Lower bitrate for wireless only, for example 1080p30 at 6 to 8 Mbps. A mostly still face holds up well in HEVC at those rates [INFERENCE].
2. 30 fps instead of 60, which about halves the data.
3. Encoder settings through scrcpy's `video_codec_options` server option: constant bitrate (`bitrate-mode=2`) so the encoder doesn't send bursts Wi-Fi has to absorb, `priority=0` for real time, no B-frames (`max-bframes=0`), and intra refresh (`intra-refresh-period`) instead of large key frames. Check in the server log which ones `c2.qti.hevc.encoder` accepts.
4. 720p.
5. A direct socket from the phone server to the Mac, skipping adb's tunnel. This needs a server patch and its own pairing and encryption, because a plain socket on the LAN is open to anyone on it. Only try it if steps 1 to 4 show the adb tunnel itself is the limit.

## Step 4: microphone check, as an end user

The app sends video only and opens the microphone only during Check Audio Sync, so the Yeti's sound goes straight to Meet without passing through the app. Talking over someone comes from round-trip delay: Willie's voice reaching Harsha late, and Harsha's reaching Willie late. Parts on Harsha's side that could add to it:

- Bluetooth headphones or AirPods, which commonly add 150 to 300 ms of playback delay [INFERENCE]. Note what was used on the call with Willie.
- The camera lag itself doesn't hold up Harsha's audio. Meet gets each frame stamped with the time it's sent, so it has no reason to delay sound to match our video [INFERENCE: how WebRTC lines up audio and video; check below].

Test:

1. Join one Meet with the Mac and a second device in the same room, with the second device's speaker on and its mic muted.
2. Clap into the Yeti and film both the clap and the second device's speaker with a phone at 120 or 240 fps. Count frames from the clap to its sound coming out.
3. Repeat with the webcam off, on over USB at 1080p30, and on at 4K60. If the delay doesn't change, our setup isn't adding to it.
4. During a real call in Chrome, open `chrome://webrtc-internals` and note the audio round-trip time and jitter buffer delay. That shows how much of the delay is the network and Meet.

## For Harsha to decide

- The latency bar above.
- If wireless meets it: a Settings option, or keep it as a hidden switch.
- Whether a direct socket (Step 3, item 5) is on the table at all.

## Done when

The numbers from Step 2 and Step 4 are in a comment on kata:android-webcam#e1f7, and `decisions.md` has a new line that either keeps USB only or replaces the 2026-10-19 USB-only line.
