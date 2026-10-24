---
type: guide
summary: How to check a Closeup change, when the emulator or phone is allowed, and why there is no ship step.
---

# Working here

- **Check:** one build, `scripts/dev.sh build`. The smoke journey (`qm with desktop NAME -- scripts/dev.sh smoke DIR`) runs only when Harsha asks or the change is to the dev control path itself (docs/dev-automation.md).
- **Devices:** the phone only after Harsha says go in chat, with the lease: `devlease take phone <you>`, then `adb -s "$(phone-connect)"`. If the lease says someone else holds the phone, stop. The checks that need it are in docs/phone-session.md.
- **Emulator:** the AVD `Webcam_A` (`qm take emu <you>`) only for work that needs a phone stand-in (adb, lens, error journeys). A normal change needs no emulator.
- **Ship:** none until the open-source release (kata:android-webcam#8ab9). The build stays in `build/`, so there is no `tend ship`.
- **Quirks:** the dev instance runs off-screen and takes the desktop only for screenshots (`qm with desktop NAME -- ...`). Don't touch `.github/workflows/`.
