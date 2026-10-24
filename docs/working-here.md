---
type: guide
summary: How to check a Closeup change, when the emulator or phone is allowed, and how it ships.
---

# Working here

- **Check:** one build, `scripts/dev.sh build`. The smoke journey (`qm with desktop NAME -- scripts/dev.sh smoke DIR`) runs only when Harsha asks or the change is to the dev control path itself (docs/dev-automation.md).
- **Devices:** the phone only after Harsha says go in chat, with the lease: `devlease take phone <you>`, then `adb -s "$(phone-connect)"`. If the lease says someone else holds the phone, stop. The checks that need it are in docs/phone-session.md.
- **Emulator:** the AVD `Webcam_A` (`qm take emu <you>`) only for work that needs a phone stand-in (adb, lens, error journeys). A normal change needs no emulator.
- **Ship:** `tend ship closeup` runs `scripts/ship.sh`: refuses a dirty tree, builds from HEAD with `scripts/build-app.sh`, quits the installed copy (not dev instances), replaces `/Applications/Closeup.app` (or `~/Applications`), relaunches it and writes `build/installed-commit`. The build is ad-hoc signed, so each install asks again for camera, microphone and local network access. Agents never run it directly.
- **Quirks:** the dev instance runs off-screen and takes the desktop only for screenshots (`qm with desktop NAME -- ...`). No GitHub Actions, ever: Actions is off on the repo, and nobody adds `.github/workflows/`.
