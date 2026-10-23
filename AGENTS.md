# closeup

## Testing

- Phone sessions start when Harsha says go in chat. Then an agent takes the phone lease (`~/.agents/skills/android-dev/scripts/devlease take phone <you>`), connects with `adb -s "$(phone-connect)" ...` (never its own `adb mdns` or `adb connect`), walks him through the checks, and releases it at the end (kata:android-webcam#bcv0).
- There's no Ship it until the open-source release. The build stays in `build/` (kata:android-webcam#8ab9).
- The phone stand-in is the AVD `Webcam_A` on emulator port 5920 (this project's range is 5920 to 5928). Boot it inside the emu line, `qm take emu <you>` first, and release it when done. It drives the off-screen dev instance through `scripts/fault-adb` (docs/dev-automation.md).
- The checks that need the phone are in docs/phone-session.md, in order.

## Docs and bugs

Docs: docs
Bugs: kata project android-webcam
Visibility: private
