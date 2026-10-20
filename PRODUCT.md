# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

Anyone with an Android phone and a Mac who wants the phone's camera as the Mac's webcam for calls and recordings. Harsha is the first user. Once it's open sourced, most users won't know adb, scrcpy or OBS, so setup help has to live in the app.

## Product Purpose

A macOS menu bar app that turns a USB-connected Android phone's camera into a Mac webcam. Success: plug in the phone, start it from the menu, pick the camera in any call or recording app, and forget about it for the whole call.

## Positioning

No app on the phone and no cloud. It runs the open-source scrcpy server over USB debugging, decodes HEVC in hardware on the Mac, and writes frames straight into the OBS Virtual Camera extension without OBS running. Free and open source.

## Operating Context

- Used right before and during video calls and recordings, often with little time to spare. Glanced at, not studied.
- The phone sits on a mount, plugged in over USB-C, often charging and getting warm.
- Requires OBS Studio's camera extension to be installed and approved once, Android 12 or later, USB debugging on, and adb from Android platform tools.
- Receiving apps seen so far: Chrome, QuickTime Player.

## Capabilities and Constraints

- Capture modes today: 4K / 60, 1080p / 60, 1080p / 30 (default), 1080p / 120 experimental. No silent resolution fallback.
- USB only (kata:android-webcam#0hz3). Keeps the OBS camera extension (kata:android-webcam#t190), which advertises 1920x1080 BGRA.
- Video only. Never records and never sends video to the Internet. The microphone opens only during the on-demand audio sync check.
- Undecided: the product name (placeholder "Phone Webcam"; "Android" can't lead the name).
- Decided 2026-10-19: Apache-2.0 license; launch at login as a setting, off by default; menu layout C (menu with a live header).

## Evidence on Hand

- One live run on 2026-10-19 with a Samsung Galaxy S25 Ultra (SM-S938U1, Android 16): picture in a call app, a QuickTime recording with a Yeti mic.
- No screenshots, users, reviews or benchmarks yet. Don't invent any.

## Product Principles

- The call comes first: never interrupt a working stream to show something.
- Say what's wrong in plain words and what to do next.
- Defaults that keep the phone cool beat maximum specs.
- Only clean up what the app created; never touch shared tools like the adb server.

## Accessibility & Inclusion

Native AppKit controls with VoiceOver labels, keyboard access to every menu item, and status that doesn't rely on color alone.
