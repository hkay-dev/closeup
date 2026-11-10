# closeup

## Testing

- Follow "Devices" in docs/working-here.md for authorized phone sessions and lease commands (kata:android-webcam#bcv0).
- The phone stand-in is the AVD `Webcam_A` on emulator port 5920 (this project's range is 5920 to 5928). Boot it only when Harsha asks for an emulator session (adb, lens, error journeys); a normal change is checked by building, with no emulator. Boot it directly, with no Quartermaster slot: `"$ANDROID_HOME/emulator/emulator" -avd Webcam_A -port 5920 -no-window`, and stop it with `adb -s emulator-5920 emu kill` when done. It drives the off-screen dev instance through `scripts/fault-adb` (docs/dev-automation.md).
- The checks that need the phone are in docs/phone-session.md, in order.

## Docs and bugs

Docs: docs
Bugs: deckhand project android-webcam
Visibility: public
