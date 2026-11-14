# closeup

## Testing

- Follow "Devices" in docs/working-here.md for authorized phone sessions and lease commands (android-webcam#bcv0).
- The phone stand-in is the AVD `Webcam_A` on emulator port 5920 (this project's range is 5920 to 5928). Boot it only when Harsha asks for an emulator session (adb, lens, error journeys); a normal change is checked by building, with no emulator. Boot it directly, with no Capacity slot: `"$ANDROID_HOME/emulator/emulator" -avd Webcam_A -port 5920 -no-window`, and stop it with `adb -s emulator-5920 emu kill` when done. It drives the off-screen dev instance through `scripts/fault-adb` (docs/dev-automation.md).
- The checks that need the phone are in docs/phone-session.md, in order.

<!-- foundry:shared start -->
## Docs and bugs

Docs: docs
Bugs: foundry project android-webcam
Visibility: public

Shared Foundry rules, written by `foundry app sync-agents` from apps.yml (change apps.yml, not this block):

- Check: `foundry capacity with build android-webcam --cwd "$PWD" --command './repo/scripts/check.sh'` from `~/Development/core/closeup` (`foundry app check android-webcam` runs it).
- Guards: no-focus, build-slots.
- Before starting or stopping a local dev server, read `~/.agents/PORTHOLE.md` and `~/.agents/WHATTHEPORT.md`. Use `devup <name> --desc "..." -- <command>`.
- If this project sends Harsha any notification (a job, hook, daemon or app), send it through `notify` or `flare-send`, never Telegram directly. Follow `flare-send guide standard` for the title and description, use a template where the data has structure, and register the sender once: `flare-send apps set <source> --name <Name> --owner <path> [--template T]`.

App facts:

- Device: S25 Ultra, Android 17 phone and the M5 Max MacBook Pro.
- Arch: arm64 only: Apple silicon Mac (no Intel) and an arm64 phone.
- No accessibility or other languages work: Harsha never wants it.
- Follow ~/Development/core/foundry/repo/docs/standards/mac-dev-builds.md for Mac builds.
- The phone only after Harsha says go, with the lease.
- No GitHub Actions, ever.
<!-- foundry:shared end -->
