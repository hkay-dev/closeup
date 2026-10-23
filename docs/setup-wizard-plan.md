---
type: plan
summary: Make first-run Setup do the Mac's part by itself (platform tools, OBS, OBS's camera) and turn the phone half into a wizard that follows the USB connection and shows the Developer options taps.
status: in-progress
covers: [Sources/AndroidWebcam/OBSSetup.swift, Sources/AndroidWebcam/USBPhones.swift, Sources/AndroidWebcam/PhoneGuide.swift, Sources/AndroidWebcam/Windows.swift, Sources/AndroidWebcam/App.swift]
---

# Setup wizard

Request: kata:android-webcam#79fh. Harsha asked that a new user only touch what macOS or the phone insists on, with clear steps and an animation of the Build number taps.

## Mac side

- **Set Up for Me** starts both downloads, then starts OBS hidden so macOS shows its camera extension box. The only click left is the switch and password in System Settings, which macOS doesn't let an app do.
- OBS's first-run windows are skipped with its own config keys, written only when OBS has never run. The keys, the launch flags and the deep link were checked in fresh macOS 27 VMs with OBS 32.2.2; screenshots are in `vm-evidence-79fh/` in the sandbox. See docs/decisions.md.
- Once the camera is on, the app quits the OBS it started.

## Phone side

- The phone step reads IOKit's USB list next to adb, so it can tell nothing plugged in from a phone with debugging off, and adb's unauthorized state from ready.
- Each state has a drawn phone acting out the taps: the cable, Build number tapped 7 times with the toasts and the PIN pad, the Developer options switch, the "Allow USB debugging?" box. The maker, from the USB vendor ID, picks the menu path.

## Checked

- Two new-user walks in clones of the plain macOS 27 base (`vm-evidence-79fh/walk-NOTES.txt`). The first found OBS restarted in a loop after approval, since the old copy saw the camera as off until it reopened; the second, after the fix, had OBS start once, no OBS window or dialog, the relaunch waiting for System Settings to close, and Setup ending at 4 of 5 with only the phone left.

## Left to check

- The USB states on a real phone: debugging off, unauthorized, allowed.
