---
type: log
summary: Changed - Flare, Porthole, Fanbar and Dotdot dev builds now run as their own "Dev" apps beside the installed ones, Fanbar Dev no longer touches the real fans, every Mac app's dev script builds through the shared build queue, and Dotdot's Mac install works again from a fresh checkout.
project: android-webcam
sprint: build-std-12-mac-fixes
window: 2026-11-05T07:31:13Z/2026-11-05T07:48:33Z
tickets: [android-webcam#ankw]
---

# Build standard review: Mac app fixes

Changed: Flare, Porthole, Fanbar and Dotdot dev builds now run as their own "Dev" apps beside the installed ones, Fanbar Dev no longer touches the real fans, every Mac app's dev script builds through the shared build queue, and Dotdot's Mac install works again from a fresh checkout.
Try: not tried yet. Start with Ship it for Dotdot's Mac app, then open Flare on the phone and send a test. One Dotdot doc commit is still on its sprint branch, because Dotdot main has an uncommitted edit to the same doc.

## What changed

- Check and ship share build/Closeup.app; dev.sh defaults (android-webcam#ankw)
