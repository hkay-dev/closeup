---
type: log
summary: Changed - All ten Mac apps now build with the one shared Xcode setup and ship through the shared ship steps, and each has the same check, dev and ship scripts that Deck runs.
project: android-webcam
sprint: build-std-3-mac
window: 2026-11-05T06:28:01Z/2026-11-05T06:43:29Z
tickets: [android-webcam#pdyc]
---

# Build standard: Mac apps

Changed: All ten Mac apps now build with the one shared Xcode setup and ship through the shared ship steps, and each has the same check, dev and ship scripts that Deck runs.
Try: not tried yet. Ship any one Mac app from Deck and watch its build page: a clean, identity, lock and requirement step come before the install.

## What changed

- Improved: Closeup builds with the full Xcode toolchain and ships through the shared install steps. (android-webcam#pdyc)

## Calls

- The ship writes the installed commit to build/stable-installed-commit, like Fanbar, because the shared record step needs a file (android-webcam#pdyc)
