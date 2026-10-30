# closeup

## Testing

- Phone sessions start when Harsha says go in chat. Then an agent takes the phone lease (`qm take phone <you> --ttl 10800`), connects with `adb -s "$(phone-connect)" ...` (never its own `adb mdns` or `adb connect`), walks him through the checks, and releases it at the end with `qm release phone <you>` (kata:android-webcam#bcv0). If `qm` says someone else holds the phone, stop; don't run the rest of the command.
- There's no Ship it until the open-source release. The build stays in `build/` (kata:android-webcam#8ab9).
- The phone stand-in is the AVD `Webcam_A` on emulator port 5920 (this project's range is 5920 to 5928). Boot it only for work that needs a phone stand-in (adb, lens, error journeys); a normal change is checked by building, with no emulator. Boot it directly, with no Quartermaster slot: `"$ANDROID_HOME/emulator/emulator" -avd Webcam_A -port 5920 -no-window`, and stop it with `adb -s emulator-5920 emu kill` when done. It drives the off-screen dev instance through `scripts/fault-adb` (docs/dev-automation.md).
- The checks that need the phone are in docs/phone-session.md, in order.

## Docs and bugs

Docs: docs
Bugs: kata project android-webcam
Visibility: public
