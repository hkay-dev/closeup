---
type: guide
summary: How to check a Closeup change, when the emulator or phone is allowed, and how it ships.
---

# Working here

## How to check

- **Check:** `deckhand app check android-webcam` builds `build/debug/Closeup.app`; Harsha tests behavior. Agents report `Try:` steps for checks that need his hands or eyes.
- **Build wrapper:** Agents run `qm with build android-webcam -- ./repo/scripts/check.sh` from `~/Development/core/closeup`. The script runs `scripts/dev.sh build`, which uses the shared Mac env's `--jobs` and toolchain without taking a second slot.
- **Quirks:** The debug bundle is separate from release `build/Closeup.app`. For design captures, start the isolated off-screen instance with `scripts/dev.sh start`; the script supplies a private `CLOSEUP_DEV_DIR` and launches the debug bundle with `open -g -j -n`. Use `qm with desktop NAME -- ...` for screenshots. Agents use captures for design work and before/after pictures, not behavior checks. Agents never add GitHub Actions workflows.
- **Hot paths:** Agents ask `reviewer` to review `Sources/Closeup/App.swift` for saved device and capture preferences, `Sources/Closeup/Wireless.swift` for phone pairing, and `Sources/Closeup/Installer.swift` for downloaded binaries, signature checks and installation.
- **Devices:** The normal check needs no phone or emulator. Harsha authorizes phone sessions in chat before an agent takes the Quartermaster phone lease: `qm take phone <you> --ttl 10800`, then `adb -s "$(phone-connect)"`, and `qm release phone <you>` at the end. Agents stop if another agent has the lease and follow `docs/phone-session.md`, the project instructions and the global device rules.

## Device and release mechanics

- **Emulator:** the AVD `Webcam_A` on port 5920, booted directly (no Quartermaster slot, see repo `AGENTS.md`), only when Harsha asks for an emulator session (adb, lens, error journeys). A normal change needs no emulator.
- **Release build:** `scripts/build-app.sh` builds release for ship and `release.sh`; `UNIVERSAL=1` also builds for Intel.
- **Ship:** `deckhand ship run android-webcam` runs `scripts/ship.sh`: follows the shared ship sequence (armada-ship-lib.sh): refuses a dirty tree, checks the signing identity, takes the ship lock, builds from HEAD with `scripts/build-app.sh` (release) under `qm with build`, signs, checks the designated requirement, then replaces `/Applications/Closeup.app` (or `~/Applications`). The install is the shared `ship_install` (armada-ship-lib.sh): unstaged it quits the installed copy (not dev instances) first and reopens it with `open -g -j` if it was running. With `ARMADA_SHIP_STAGED=1` the running copy keeps running: it is moved aside to a hidden `.Closeup-old.*` folder until it quits and the new build goes in at `Closeup.app`, since macOS loses a running app's code identity (and its camera grant) when its files go (android-webcam#6fx8). Deck's default Restart quits and reopens Closeup, which then runs the new build; there is no `restart` subcommand or pending folder. Deckhand records the installed commit. Every build is signed with "Vesper Self-Signed" (the one self-signed certificate all Mac apps share, login keychain), dev builds too, so camera, microphone and local network grants carry across ships. The first build under it resets the grants once (android-webcam#zcr3); the old "Closeup Local Signing" certificate stays in the keychain, unused. Dev and stable both keep the bundle id `com.harsha.closeup` (build-app.sh makes one bundle for both), so a dev instance is told apart by `CLOSEUP_DEV_DIR`, not by id. Agents never run it directly.
